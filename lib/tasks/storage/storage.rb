##
# Helper class to:
#   1. migrate file into ActiveStorage
#   2. mirror ActiveStorage blobs between secondary mirrors
#   3. promote ActiveStorage secondary mirrors to serve blobs data
#
# Require a ActiveRecord class and symbol representing the has_one_attached
# association.
#
class Storage
  def initialize(klass, association, setter: :data=, getter: :data,
                 condition: nil)
    @klass = klass
    @association = association
    @setter = setter
    @getter = getter
    @condition = condition
  end

  def migrate
    count = unattached_files.count

    unattached_files.find_each.with_index do |file, index|
      Kernel.silence_warnings do
        do_migrate = true
        do_migrate = @condition.call(file) if @condition
        file.public_send(@setter, file.public_send(@getter)) if do_migrate
      end

      print "#{prefix}: Migrated #{index + 1}/#{count}"

    rescue Errno::ENOENT
      erase_line
      Kernel.silence_warnings do
        $stderr.puts "#{prefix};ID=#{file.id}: Missing #{file.filepath}."
      end
    end

    puts "#{prefix}: Migrated old files storage to #{service_name} completed."
  end

  def mirror
    return puts(not_a_mirror) unless mirror_service?
    return puts(mirror_primary_not_disk_service) unless disk_service?

    count = mirrorable_blobs.count

    mirrorable_blobs.find_each.with_index do |blob, index|
      begin
        mirror_service.mirror(blob.key, checksum: blob.checksum)
      rescue ActiveStorage::IntegrityError => ex
        raise ex unless @klass == FoiAttachment

        # Fix for https://github.com/mysociety/alaveteli/issues/8181
        attachment = FoiAttachment.joins(:file_blob).
          find_by(active_storage_blobs: { id: blob })
        # Running the attachment masking will also mirror the file
        FoiAttachmentMaskJob.set(queue: :low).perform_later(attachment)
      end

      print "#{prefix}: Mirrored #{index + 1}/#{count}"
    end

    puts "#{prefix}: Mirrored from #{disk_service.name} to " \
         "#{secondary_service.name} completed."
  end

  def promote
    return puts(not_a_mirror) unless mirror_service?
    return puts(mirror_primary_not_disk_service) unless disk_service?

    count = promotable_blobs.count

    promotable_blobs.find_each.with_index do |blob, index|
      next unless secondary_service.exist?(blob.key)

      blob.update(service_name: secondary_service.name)

      print "#{prefix}: Promote #{index + 1}/#{count}"
    end

    puts "#{prefix}: Promoted blobs in #{disk_service.name} to " \
         "#{secondary_service.name} completed."
  end

  def unlink
    return puts(not_a_mirror) unless mirror_service?
    return puts(mirror_primary_not_disk_service) unless disk_service?

    count = secondary_blobs.count

    secondary_blobs.find_each.with_index do |blob, index|
      next unless disk_service.exist?(blob.key)

      disk_service.delete(blob.key)

      print "#{prefix}: Unlink #{index + 1}/#{count}"
    end

    puts "#{prefix}: Unlinked files in #{disk_service.name} completed."
  end

  private

  def unattached_files
    @klass.left_joins(:"#{@association}_attachment").where(
      active_storage_attachments: { id: nil }
    )
  end

  def blobs
    ActiveStorage::Blob.joins(:attachments).where(
      active_storage_attachments: {
        name: @association, record_type: @klass.to_s
      }
    )
  end

  def mirrorable_blobs
    blobs.where(service_name: mirror_service.name)
  end

  def promotable_blobs
    mirrorable_blobs.where(created_at: (..7.days.ago))
  end

  def secondary_blobs
    blobs.where(service_name: secondary_service.name)
  end

  def attachment
    @klass.reflect_on_attachment(@association)
  end

  def service_name
    attachment.options[:service_name]
  end

  def service
    ActiveStorage::Blob.services.fetch(service_name)
  end

  def mirror_service?
    service.respond_to?(:mirror)
  end

  def mirror_service
    raise not_a_mirror unless mirror_service?

    service
  end

  def not_a_mirror
    "#{prefix}: Not using the mirror service, ensure config/storage.yml is " \
    "correct. See: " \
    "https://alaveteli.org/docs/installing/storage/#mirrored-services"
  end

  def mirror_primary_not_disk_service
    "#{prefix}: Mirror primary service is not a disk service, ensure " \
    "config/storage.yml is correct. See: " \
    "https://alaveteli.org/docs/installing/storage/#mirrored-services"
  end

  def disk_service
    raise mirror_primary_not_disk_service unless disk_service?

    mirror_service.primary
  end

  def disk_service?
    mirror_service.primary.is_a?(ActiveStorage::Service::DiskService)
  end

  def secondary_service
    mirror_service.mirrors.first
  end

  def prefix
    @klass.to_s
  end

  def puts(*args)
    return unless Rake.verbose

    erase_line
    $stdout.puts(*args)
  end

  def print(*args)
    return unless Rake.verbose

    erase_line
    $stdout.print(*args)
  end

  def erase_line
    # https://en.wikipedia.org/wiki/ANSI_escape_code#Escape_sequences
    $stdout.print "\e[1G\e[K"
  end
end
