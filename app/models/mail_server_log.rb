# == Schema Information
# Schema version: 20210114161442
#
# Table name: mail_server_logs
#
#  id                      :integer          not null, primary key
#  mail_server_log_done_id :integer
#  info_request_id         :integer
#  order                   :integer          not null
#  line                    :text             not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  delivery_status         :string
#

# We load log file lines for requests in here, for display in the admin interface.
#
# Copyright (c) 2009 UK Citizens Online Democracy. All rights reserved.
# Email: hello@mysociety.org; WWW: http://www.mysociety.org/

class MailServerLog < ApplicationRecord
  # `serialize` needs to be called before all other ActiveRecord code.
  # See http://stackoverflow.com/a/15610692/387558
  serialize :delivery_status, coder: DeliveryStatusSerializer

  belongs_to :info_request,
             inverse_of: :mail_server_logs,
             optional: true
  belongs_to :mail_server_log_done,
             inverse_of: :mail_server_logs,
             optional: true

  before_create :calculate_delivery_status

  # Load in exim or postfix log file from disk, or update if we already have it
  # Assumes files are named with date, rather than cyclically.
  # Doesn't do anything if file hasn't been modified since it was last loaded.
  # Note: If you do use rotated log files (rather than files named by date), at some
  # point old loaded log lines will get deleted in the database.
  def self.load_file(file_name)
    is_gz = file_name.include?(".gz")
    file_name_db = is_gz ? file_name.gsub(".gz", "") : file_name

    modified = File.stat(file_name).mtime
    if modified.nil?
      raise "MailServerLog.load_file: file not found " + file_name
    end

    ActiveRecord::Base.transaction do
      # see if we already have it
      done = MailServerLogDone.find_by_filename(file_name_db)
      if done
        if modified.utc == done.last_stat.utc
          # already have that, nothing to do
          return
        else
          MailServerLog.where("mail_server_log_done_id = ?", done.id).delete_all
        end
      else
        done = MailServerLogDone.new(filename: file_name_db)
      end
      done.last_stat = modified
      # update done structure so we know when we last read this file
      done.save!

      f = is_gz ? Zlib::GzipReader.open(file_name) : File.open(file_name, 'r')
      case(AlaveteliConfiguration.mta_log_type.to_sym)
      when :exim
        load_exim_log_data(f, done)
      when :postfix
        load_postfix_log_data(f, done)
      else
        raise "Unexpected MTA type: #{type}"
      end
      f.close
    end
  end

  # Scan the file
  def self.load_exim_log_data(f, done)
    order = 0
    f.each do |line|
      order += 1
      create_exim_log_line(line, done, order)
    end
  end

  def self.load_postfix_log_data(f, done)
    order = 0
    emails = scan_for_postfix_queue_ids(f)
    # Go back to the beginning of the file
    f.rewind
    f.each do |line|
      sanitised_line = scrub(line)
      order += 1
      queue_id = extract_postfix_queue_id_from_syslog_line(sanitised_line)
      if emails.key?(queue_id)
        create_mail_server_logs(emails[queue_id], sanitised_line, order, done)
      end
    end
  end

  def self.scan_for_postfix_queue_ids(f)
    result = {}
    f.each do |line|
      emails = email_addresses_on_line(line)
      queue_id = extract_postfix_queue_id_from_syslog_line(line)
      result[queue_id] = [] unless result.key?(queue_id)
      result[queue_id] = (result[queue_id] + emails).uniq
    end
    result
  end

  # Returns nil if there is no queue id
  def self.extract_postfix_queue_id_from_syslog_line(line)
    # Assume the log file was written using syslog and parse accordingly
    m = SyslogProtocol.parse("<13>" + line).content.match(/^\S+: (\S+):/)
    m[1] if m
  end

  # We also check the email prefix so that we could, for instance, separately handle a staging and production
  # instance running on the same server with different email prefixes.
  def self.email_addresses_on_line(line)
    prefix = Regexp.quote(AlaveteliConfiguration.incoming_email_prefix)
    domain = Regexp.quote(AlaveteliConfiguration.incoming_email_domain)
    line.scan(/#{prefix}request-[^\s]+@#{domain}/).sort.uniq
  end

  def self.request_sent?(ir)
    case(AlaveteliConfiguration.mta_log_type.to_sym)
    when :exim
      request_exim_sent?(ir)
    when :postfix
      request_postfix_sent?(ir)
    else
      raise "Unexpected MTA type: #{type}"
    end
  end

  # Look at the log for a request and check that an email was delivered
  def self.request_exim_sent?(ir)
    # Look for line showing request was sent
    found = false
    ir.mail_server_logs.each do |mail_server_log|
      test_outgoing = " <= " + ir.incoming_email + " "
      if mail_server_log.line.include?(test_outgoing)
        # Check the from value is the same (it always will be, but may as well
        # be sure we are parsing the exim line right)
        envelope_from = " from <" + ir.incoming_email + "> "
        if !mail_server_log.line.include?(envelope_from)
          $stderr.puts("unexpected parsing of exim line: [#{mail_server_log.line.chomp}]")
        else
          found = true
        end
      end
    end
    found
  end

  def self.request_postfix_sent?(ir)
    # dsn=2.0.0 is the magic word that says that postfix delivered the email
    # See http://tools.ietf.org/html/rfc3464
    ir.mail_server_logs.any? { |l| l.line.include?("dsn=2.0.0") }
  end

  # Check that the last day of requests has been sent in Exim or Postfix and we got the
  # lines. Writes any errors to STDERR. This check is really mainly to
  # check the envelope from is the request address, as Ruby is quite
  # flaky with regard to that, and it is important for anti-spam reasons.
  # TODO: does this really check that, as the log just wouldn't pick
  # up at all if the requests weren't sent that way as there would be
  # no request- email in it?
  #
  # NB: There can be several emails involved in a request. This just checks that
  # at least one of them has been successfully sent.
  #
  def self.check_recent_requests_have_been_sent
    # Get all requests sent for from 2 to 10 days ago. The 2 day gap is
    # because we load mail server log lines via cron at best an hour after they
    # are made)
    info_requests = InfoRequest.where("created_at < ?
                                      AND created_at > ?
                                      AND user_id IS NOT null",
                                      Time.zone.now - 2.days,
                                      Time.zone.now - 10.days)

    # Go through each request and check it
    ok = true
    info_requests.each do |info_request|
      unless request_sent?(info_request)
        # It's very important the envelope from is set for avoiding spam filter reasons - this
        # effectively acts as a check for that.

        # *** don't comment out this STDERR line, it is the point of the function!
        $stderr.puts("failed to find request sending in MTA logs for request " \
                     "id #{info_request.id} #{info_request.url_title} (check " \
                     "envelope from is being set to request address in Ruby, " \
                     "and load-mail-server-logs crontab is working)")
        ok = false
      end
    end
    ok
  end

  def self.create_exim_log_line(line, done, order = 1)
    sanitised_line = scrub(line)
    emails = email_addresses_on_line(sanitised_line)
    create_mail_server_logs(emails, sanitised_line, order, done)
  end

  def is_owning_user?(user)
    info_request.is_owning_user?(user)
  end

  # Public: Overrides the ActiveRecord attribute accessor
  #
  # opts = Hash of options (default: {})
  #        :redact - Redacts potentially sensitive information from the line
  #        :decorate - Wrap the line in a decorator appropriate to the MTA
  #
  # Returns a String, EximLine or PostfixLine
  def line(opts = {})
    _line = read_attribute(:line)

    if opts[:redact]
      _line = strip_syslog_prefix(_line)
      _line = redact_hostname(_line) if sent_to_smarthost?(_line)
      _line =
        redact_idhash(_line, info_request.idhash) if info_request.try(:idhash)
    end

    _line = line_decorator.new(_line) if opts[:decorate]
    _line
  end

  def delivery_status
    unless attributes['delivery_status'].present?
      # attempt to parse the status from the log line and store if successful
      set_delivery_status
    end

    DeliveryStatusSerializer.load(read_attribute(:delivery_status))
  # TODO: This rescue can be removed when there are no more cached
  # MTA-specific statuses

  rescue ArgumentError
    warn %q(MailServerLog#delivery_status rescuing from invalid delivery
            status. Run bundle exec rake temp:cache_delivery_status to update
            cached values. This error handling will be removed soon.).
            squish unless Rails.env.test?

    # re-try setting the delivery status, forcing the write by avoiding the
    # Rails 4.2 call to old_attribute_value hidden inside write_attribute as
    # that will re-raise the 'Invalid delivery status' ArgumentError we're
    # attempting to rescue
    # https://apidock.com/rails/v4.2.7/ActiveRecord/AttributeMethods/Dirty/write_attribute
    set_delivery_status(true)
    save!
    DeliveryStatusSerializer.load(read_attribute(:delivery_status))
  end

  private

  # attempt to parse the status from the log line and store if successful
  def set_delivery_status(force = false)
    decorated = line(decorate: true)
    if decorated && decorated.delivery_status
      if force
        force_delivery_status(decorated.delivery_status)
      else
        self.delivery_status = decorated.delivery_status
      end
    end
  end

  def force_delivery_status(new_status)
    # write the value without checking the old (invalid) value, avoiding the
    # unintended ArgumentError caused by reading the old value
    update_columns(delivery_status: new_status)

    # record the new value in `changes` so that save will have something to do
    # as update_columns just updates the value
    delivery_status_will_change!
  end

  def calculate_delivery_status
    delivery_status
    true
  end

  def self.create_mail_server_logs(emails, line, order, done)
    emails.each do |email|
      info_request = InfoRequest.find_by_incoming_email(email)
      if info_request
        info_request.
          mail_server_logs.
          create!(line: line, order: order, mail_server_log_done: done)
      end
    end
  end
  private_class_method :create_mail_server_logs

  def line_decorator
    mta = AlaveteliConfiguration.mta_log_type.to_sym
    case mta
    when :exim
      EximLine
    when :postfix
      PostfixLine
    else
      raise "Unexpected MTA type: #{ mta }"
    end
  end

  def strip_syslog_prefix(line)
    prefix_regexp = /\A(.*?\s)\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}.*/
    match = line.match(prefix_regexp).try(:[], 1)
    if match
      line.gsub(match, '')
    else
      line
    end
  end

  def sent_to_smarthost?(line)
    line.match(/R=(\w+)/).try(:[], 1).to_s.downcase == 'send_to_smarthost'
  end

  def redact_hostname(line)
    hostname_regexp = /H=(.*?\s\[\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\]\:\d{1,5})/
    match = line.match(hostname_regexp).try(:[], 1)
    if match
      line.gsub(match, _('[REDACTED]'))
    else
      line
    end
  end

  def redact_idhash(line, idhash)
    line.gsub(idhash, _('[REDACTED]'))
  end
end
