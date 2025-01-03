##
# Class responsible for loading external blog content
#
# Requires `BLOG_FEED` to be configured in config/general.yml
#
# Currently WordPress is the only "officially supported" external blog feed,
# but other feeds may work if they use the same data format.
#
class Blog
  include ConfigHelper

  def self.enabled?
    AlaveteliConfiguration.blog_feed.present?
  end

  def self.table_name_prefix
    'blog_'
  end

  def posts
    return [] if content.empty?

    posts = XmlSimple.xml_in(content)['channel'][0].fetch('item', []).reverse
    posts.map do |data|
      Blog::Post.find_or_initialize_by(url: data['link'][0]).tap do |post|
        post.update(title: data['title'][0], data: data)
      end
    end.reverse
  end

  def feeds
    [{ url: feed_url, title: "#{site_name} blog" }]
  end

  def feed_url
    uri = URI(AlaveteliConfiguration.blog_feed)
    uri.query = URI.decode_www_form(uri.query || '').to_h.merge(
      lang: AlaveteliLocalization.html_lang.to_s
    ).to_param
    uri.to_s
  end

  private

  def content
    @content ||= quietly_try_to_open(feed_url, timeout)
  end

  def timeout
    AlaveteliConfiguration.blog_timeout.presence || 60
  end
end
