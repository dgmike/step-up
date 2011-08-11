module StepUp
  module Driver
    class Git < Base
      VERSION_MESSAGE_FILE_PATH = ".git/TAG_EDITMSG"
      NOTE_MESSAGE_FILE_PATH = ".git/NOTE_EDITMSG"
      
      include GitExtensions::Notes

      def unsupported_scm_banner
        if `git --version`.chomp =~ /\d\.[^\s]+/
          v = $&
          if Gem::Version.correct?(v)
            if Gem::Version.new("1.7.1") > Gem::Version.new(v)
              "Unsupported installed GIT version: #{v}\n" +
              "Please install version 1.7.1 or newer"
            end
          else
            "Installed GIT version unknown: #{v}"
          end
        else
          super
        end
      end

      def self.last_version
        new.last_version_tag
      end

      def empty_repository?
        `git branch`.empty?
      end

      def commit_history(commit_base, *args)
        return [] if empty_repository?
        options = args.last.is_a?(Hash) ? args.pop : {}
        top = args.shift
        top = "-n#{ top }" unless top.nil?
        commits = `git log --pretty=oneline --no-color #{ top } #{ commit_base }`
        if options[:with_messages]
          commits.scan(/^(\w+)\s+(.*)$/)
        else
          commits.scan(/^(\w+)\s/).flatten
        end
      end

      def commits_between(first_commit, last_commit = "HEAD", *args)
        commit_base = first_commit.nil? ? last_commit : "#{ first_commit }..#{ last_commit }"
        commit_history(commit_base, *args)
      end

      def tags
        @tags ||= `git tag -l`
      end

      def objects_with_notes_of(ref)
        `git notes --ref=#{ ref } list`.scan(/\w+$/)
      end

      def note_message(ref, commit)
        `git notes --ref=#{ ref } show #{ commit }`
      end

      def all_version_tags
        @version_tags ||= tags.scan(mask.regex).map{ |tag| tag.collect(&:to_i) }.sort.map{ |tag| mask.format(tag) }.reverse
      end

      def version_tag_info(tag)
        full_message = `git show #{ tag }`
        tag_pattern = tag.gsub(/\./, '\\.')
        tag_message = full_message[/^tag\s#{tag_pattern}.*?\n\n(.*?)\n\n(?:tag\s[^\s]+|commit\s\w{40})\n/m, 1] || ""
        tagger = full_message[/\A.*?\nTagger:\s(.*?)\s</m, 1]
        date = Time.parse(full_message[/\A.*?\nDate:\s+(.*?)\n/m, 1])
        {:message => tag_message, :tagger => tagger, :date => date}
      end

      def detached_notes_as_hash(commit_base = "HEAD", notes_sections = nil)
        tag = all_version_tags.any? ? cached_last_version_tag(commit_base) : nil
        tag = tag.sub(/\+$/, '') unless tag.nil?
        RangedNotes.new(self, tag, commit_base, :notes_sections => notes_sections).notes.as_hash
      end

      def steps_to_increase_version(level, commit_base = "HEAD", message = nil)
        tag = cached_last_version_tag(commit_base)
        tag = tag.sub(/\+$/, '')
        new_tag = mask.increase_version(tag, level)
        notes = cached_detached_notes_as_hash(commit_base)
        commands = []
        commands << "git fetch" if cached_fetched_remotes.any?
        commands << "git tag -a -m \"#{ (message || notes.to_changelog).gsub(/([\$\\"`])/, '\\\\\1') }\" #{ new_tag } #{ commit_base }"
        commands << "git push #{cached_fetched_remotes("notes").first} refs/tags/#{new_tag}" if cached_fetched_remotes.any?
        commands + steps_for_archiving_notes(notes, new_tag)
      end

      def last_version_tag(commit_base = "HEAD", count_commits = false)
        all_versions = all_version_tags
        unless all_versions.empty?
          commits = cached_commit_history(commit_base)
          all_versions.each do |tag|
            commit_under_the_tag = commit_history(tag, 1).first
            index = commits.index(commit_under_the_tag)
            unless index.nil?
              unless index.zero?
                count = count_commits == true ? commits_between(tag, commit_base).size : 0
                tag = "#{ tag }+#{ count unless count.zero? }"
              end
              return tag
            end
          end
          no_tag_version_in_commit_history = nil
        else
          zero_version(commit_base, count_commits)
        end
      end

      def fetched_remotes(refs_type = 'heads')
        config = `git config --get-regexp 'remote'`.split(/\n/)
        config.collect{ |line|
          $1 if line =~ /^remote\.(\w+)\.fetch\s\+refs\/#{ refs_type }/
        }.compact.uniq.sort
      end

      def editor_name
        ENV["GIT_EDITOR"] || ENV["EDITOR"] || `git config core.editor`.chomp
      end

      def zero_version(commit_base = "HEAD", count_commits = false)
        "%s+%s" % [mask.blank, "#{ tags.empty? ? '0' : commit_history(commit_base).size if count_commits }"]
      end
    end
  end
end
