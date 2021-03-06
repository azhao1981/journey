module Journey
  module Path
    class Pattern
      attr_reader :spec, :requirements, :anchored

      def initialize strexp
        parser = Journey::Parser.new

        @anchored = true

        case strexp
        when String
          @spec         = parser.parse strexp
          @requirements = {}
          @separators   = "/.?"
        when Router::Strexp
          @spec         = parser.parse strexp.path
          @requirements = strexp.requirements
          @separators   = strexp.separators.join
          @anchored     = strexp.anchor
        else
          raise "wtf bro: #{strexp}"
        end

        @names          = nil
        @optional_names = nil
        @required_names = nil
        @re = nil
      end

      def names
        @names ||= spec.grep(Nodes::Symbol).map { |n| n.children.tr(':', '') }
      end

      def required_names
        @required_names ||= names - optional_names
      end

      def optional_names
        @optional_names ||= spec.grep(Nodes::Group).map { |group|
          group.grep(Nodes::Symbol)
        }.flatten.map { |n| n.children.tr ':', '' }.uniq
      end

      class RegexpOffsets < Journey::Visitors::Visitor # :nodoc:
        attr_reader :offsets

        def initialize matchers
          @matchers      = matchers
          @capture_count = [0]
        end

        def visit node
          super
          @capture_count
        end

        def visit_SYMBOL node
          node = node.to_sym

          if @matchers.key? node
            re = /#{@matchers[node]}|/
            @capture_count.push((re.match('').length - 1) + (@capture_count.last || 0))
          else
            @capture_count << (@capture_count.last || 0)
          end
        end
      end

      class AnchoredRegexp < Journey::Visitors::Visitor # :nodoc:
        def initialize separator, matchers
          @separator = separator
          @matchers  = matchers
          @separator_re = "([^#{separator}]+)"
          super()
        end

        def accept node
          %r{\A#{visit node}\Z}
        end

        def visit_CAT node
          [visit(node.left), visit(node.right)].join
        end

        def visit_SYMBOL node
          node = node.to_sym

          return @separator_re unless @matchers.key? node

          re = @matchers[node]
          # FIXME: is the question mark needed?
          "(#{re}?)"
        end

        def visit_GROUP node
          "(?:#{visit node.value})?"
        end

        def visit_LITERAL node
          Regexp.escape node.value
        end
        alias :visit_DOT :visit_LITERAL

        def visit_SLASH node
          node.value
        end

        def visit_STAR node
          "(.+)"
        end
      end

      class UnanchoredRegexp < AnchoredRegexp # :nodoc:
        def accept node
          %r{\A#{visit node}}
        end
      end

      class MatchData
        attr_reader :names

        def initialize names, offsets, match
          @names   = names
          @offsets = offsets
          @match   = match
        end

        def captures
          (length - 1).times.map { |i| self[i + 1] }
        end

        def [] x
          idx = @offsets[x - 1] + x
          @match[idx]
        end

        def length
          @offsets.length
        end

        def post_match
          @match.post_match
        end

        def to_s
          @match.to_s
        end
      end

      def match other
        return unless match = to_regexp.match(other)
        MatchData.new names, offsets, match
      end
      alias :=~ :match

      def source
        to_regexp.source
      end

      private
      def to_regexp
        @re ||= regexp_visitor.new(@separators, @requirements).accept spec
      end

      def regexp_visitor
        @anchored ? AnchoredRegexp : UnanchoredRegexp
      end

      def offsets
        viz = RegexpOffsets.new @requirements
        viz.accept spec
      end
    end
  end
end
