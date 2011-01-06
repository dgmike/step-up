module StepUp
  module Driver
    class Git
      include GitExtensions::Notes
      attr_reader :mask
      def initialize
        @mask = Parser::VersionMask.new(CONFIG.versioning.version_mask)
      end

      def self.last_version
        new.last_version_tag
      end

      def commit_history(commit_base, *args)
        options = args.last.is_a?(Hash) ? args.pop : {}
        top = args.shift
        top = "-n#{ top }" unless top.nil?
        commits = `git log --pretty=oneline --no-color --no-notes #{ top } #{ commit_base }`
        if options[:with_messages]
          commits.split(/\n/).map{ |commit| commit =~ /^(\w+)\s+(.*)$/ ? [$1, $2] : nil }
        else
          commits.gsub(/^(\w+)\s.*$/, '\1').split(/\n/)
        end
      end

      def commits_between(first_commit, last_commit = "HEAD", *args)
        commit_base = first_commit.nil? ? last_commit : "#{ first_commit }..#{ last_commit }"
        commit_history(commit_base, *args)
      end

      def all_tags
        `git tag -l`.split("\n")
      end

      def objects_with_notes_of(ref)
        `git notes --ref=#{ ref } list`.gsub(/^\w+\s(\w+)$/, '\1').split(/\n/)
      end

      def note_message(ref, commit)
        `git notes --ref=#{ ref } show #{ commit }`
      end

      def notes_messages(objects_with_notes)
        objects_with_notes.messages
      end

      def all_version_tags
        @version_tags ||= all_tags.map{ |tag| mask.parse(tag) }.compact.sort.map{ |tag| mask.format(tag) }.reverse
      end

      def steps_to_increase_version(level, commit_base = "HEAD")
        tag = last_version_tag(commit_base)
        tag = tag.sub(/\+$/, '')
        new_tag = mask.increase_version(tag, level)
        message = RangedNotes.new(self, tag, commit_base).notes.as_hash
        commands = []
        commands << "git fetch"
        commands << "git tag -a -m \"#{ message.to_changelog.gsub(/([\$\\"])/, '\\\\\1') }\" #{ new_tag }"
        commands << "git push --tags"
        commands + steps_for_archiving_notes(message, new_tag)
      end

      def last_version_tag(commit_base = "HEAD", count_commits = false)
        all_versions = all_version_tags
        unless all_versions.empty?
          commits = commit_history(commit_base)
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
        ENV["EDITOR"] || `git config core.editor`.chomp
      end

      def zero_version(commit_base = "HEAD", count_commits = false)
        "%s+%s" % [mask.blank, "#{ commit_history(commit_base).size if count_commits }"]
      end
    end
  end
end
