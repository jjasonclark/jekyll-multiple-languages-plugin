require "jekyll/multiple/languages/plugin/version"

module Jekyll
  @parsedlangs = {}
  def self.langs
    @parsedlangs
  end
  def self.setlangs(l)
    @parsedlangs = l
  end

  def self.lookup_translation(site, key)
    lang = site.config['lang']
    unless Jekyll.langs.has_key?(lang)
      Jekyll.logger.warn "Loading translation from file #{site.source}/_i18n/#{lang}.yml"
      Jekyll.langs[lang] = YAML.load_file("#{site.source}/_i18n/#{lang}.yml")
    end
    translation = Jekyll.langs[lang].access(key) if key.is_a?(String)
    if translation.nil? || translation.empty?
      Jekyll.logger.abort_with "Missing i18n key: #{lang}:#{key}"
    end
    translation
  end

  class Page
    alias :read_yaml_org :read_yaml
    def read_yaml(base, name, opts = {})
      read_yaml_org(base, name, opts)
      if data['translated_name']
        translation = Jekyll.lookup_translation(site, data['translated_name'])
        self.ext = File.extname(translation)
        self.basename = translation[0 .. -ext.length - 1]
      end
    end
  end

  class Site
    alias :process_org :process
    def process
      if !self.config['baseurl']
        self.config['baseurl'] = ""
      end
      #Variables
      config['baseurl_root'] = self.config['baseurl']
      baseurl_org = self.config['baseurl']
      languages = self.config['languages']
      dest_org = self.dest

      #Loop
      languages.each do |lang|

        # Build site for language lang
        @dest = @dest + "/" + lang
        self.config['baseurl'] = self.config['baseurl'] + "/" + lang
        self.config['lang'] = lang
        Jekyll.logger.info "Building site for language: \"#{self.config['lang']}\" to: #{self.dest}"
        process_org

        #Reset variables for next language
        @dest = dest_org
        self.config['baseurl'] = baseurl_org
      end
      Jekyll.setlangs({})
      Jekyll.logger.info 'Build complete'
    end

    alias :read_posts_org :read_posts
    def read_posts(dir)
      if dir == ''
        read_posts("_i18n/#{self.config['lang']}/")
      else
        read_posts_org(dir)
      end
    end
  end

  class LocalizeTag < Liquid::Tag

    def initialize(tag_name, key, tokens)
      super
      @key = key.strip
    end

    def render(context)
      if "#{context[@key]}" != "" #Check for page variable
        key = "#{context[@key]}"
      else
        key = @key
      end
      Jekyll.lookup_translation(context.registers[:site], key)
    end
  end

  module Tags
    class LocalizeInclude < IncludeTag
      def render(context)
        if "#{context[@file]}" != "" #Check for page variable
          file = "#{context[@file]}"
        else
          file = @file
        end

        includes_dir = File.join(context.registers[:site].source, '_i18n/' + context.registers[:site].config['lang'])

        if File.symlink?(includes_dir)
          return "Includes directory '#{includes_dir}' cannot be a symlink"
        end
        if file !~ /^[a-zA-Z0-9_\/\.-]+$/ || file =~ /\.\// || file =~ /\/\./
          return "Include file '#{file}' contains invalid characters or sequences"
        end

        Dir.chdir(includes_dir) do
          choices = Dir['**/*'].reject { |x| File.symlink?(x) }
          if choices.include?(file)
            source = File.read(file)
            partial = Liquid::Template.parse(source)

            context.stack do
              context['include'] = parse_params(context) if @params
              contents = partial.render(context)
              site = context.registers[:site]
              ext = File.extname(file)

              converter = site.converters.find { |c| c.matches(ext) }
              contents = converter.convert(contents) unless converter.nil?

              contents
            end
          else
            "Included file '#{file}' not found in #{includes_dir} directory"
          end
        end
      end
    end
  end
end

unless Hash.method_defined? :access
  class Hash
    def access(path)
      ret = self
      path.split('.').each do |p|
        if p.to_i.to_s == p
          ret = ret[p.to_i]
        else
          ret = ret[p.to_s] || ret[p.to_sym]
        end
        break unless ret
      end
      ret
    end
  end
end

Liquid::Template.register_tag('t', Jekyll::LocalizeTag)
Liquid::Template.register_tag('translate', Jekyll::LocalizeTag)
Liquid::Template.register_tag('tf', Jekyll::Tags::LocalizeInclude)
Liquid::Template.register_tag('translate_file', Jekyll::Tags::LocalizeInclude)
