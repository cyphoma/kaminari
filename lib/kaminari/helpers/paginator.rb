require 'active_support/inflector'
require 'action_view'
require 'action_view/log_subscriber'
require 'action_view/context'
require 'kaminari/helpers/tags'
require 'core_ext/numeric'

module Kaminari
  module Helpers
    # The main container tag
    class Paginator < Tag
      # so that this instance can actually "render"
      include ::ActionView::Context

      def initialize(template, options) #:nodoc:
        #FIXME for compatibility. remove num_pages at some time in the future
        options[:total_pages] ||= options[:num_pages]
        options[:num_pages] ||= options[:total_pages]

        @window_options = {}.tap do |h|
          h[:window] = options.delete(:window) || options.delete(:inner_window) || Kaminari.config.window
          outer_window = options.delete(:outer_window) || Kaminari.config.outer_window
          h[:left] = options.delete(:left) || Kaminari.config.left
          h[:left] = outer_window if h[:left] == 0
          h[:right] = options.delete(:right) || Kaminari.config.right
          h[:right] = outer_window if h[:right] == 0
          decade = options.delete(:decade) || Kaminari.config.decade
          h[:decade_left] = options.delete(:decade_left) || Kaminari.config.decade_left
          h[:decade_left] = decade if h[:decade_left] == 0
          h[:decade_right] = options.delete(:decade_right) || Kaminari.config.decade_right
          h[:decade_right] = decade if h[:decade_right] == 0
        end
        @template, @options = template, options
        @theme = @options[:theme] ? "#{@options[:theme]}/" : ''
        @window_options.merge! @options
        @window_options[:current_page] = @options[:current_page] = PageProxy.new(@window_options, @options[:current_page], nil)

        @last = nil
        # initialize the output_buffer for Context
        @output_buffer = ActionView::OutputBuffer.new

        @left_decade = 1.decadeup(@window_options[:decade_left] * 10).to_a
        @right_decade = @window_options[:total_pages].decadedown(@window_options[:total_pages] - @window_options[:decade_right] * 10).to_a
      end

      # render given block as a view template
      def render(&block)
        instance_eval(&block) if @options[:total_pages] > 1
        @output_buffer
      end

      # enumerate each page providing PageProxy object as the block parameter
      # Because of performance reason, this doesn't actually enumerate all pages but pages that are seemingly relevant to the paginator.
      # "Relevant" pages are:
      # * pages inside the left outer window plus one for showing the gap tag
      # * pages inside the left decade
      # * pages inside the inner window plus one on the left plus one on the right for showing the gap tags
      # * pages inside the right decade
      # * pages inside the right outer window plus one for showing the gap tag
      def each_relevant_page
        return to_enum(:each_relevant_page) unless block_given?

        relevant_pages(@window_options).each do |i|
          yield PageProxy.new(@window_options, i, @last, @left_decade, @right_decade)
        end
      end
      alias each_page each_relevant_page

      def relevant_pages(options)
        left_window_plus_one = 1.upto(options[:left] + 1).to_a
        right_window_plus_one = (options[:total_pages] - options[:right]).upto(options[:total_pages]).to_a
        inside_window_plus_each_sides = (options[:current_page] - options[:window] - 1).upto(options[:current_page] + options[:window] + 1).to_a
        left_decade = @left_decade
        right_decade = @right_decade

        (left_window_plus_one + left_decade + inside_window_plus_each_sides + right_decade + right_window_plus_one).uniq.sort.reject {|x| (x < 1) || (x > options[:total_pages])}
      end
      private :relevant_pages

      def page_tag(page)
        @last = Page.new @template, @options.merge(:page => page)
      end

      %w[first_page prev_page next_page last_page gap].each do |tag|
        eval <<-DEF
          def #{tag}_tag
            @last = #{tag.classify}.new @template, @options
          end
        DEF
      end

      def to_s #:nodoc:
        subscriber = ActionView::LogSubscriber.log_subscribers.detect {|ls| ls.is_a? ActionView::LogSubscriber}

        # There is a logging subscriber
        # and we don't want it to log render_partial
        # It is threadsafe, but might not repress logging
        # consistently in a high-load environment
        if subscriber
          unless defined? subscriber.render_partial_with_logging
            class << subscriber
              alias_method :render_partial_with_logging, :render_partial
              attr_accessor :render_without_logging
              # ugly hack to make a renderer where
              # we can turn logging on or off
              def render_partial(event)
                render_partial_with_logging(event) unless render_without_logging
              end
            end
          end

          subscriber.render_without_logging = true
          ret = super @window_options.merge :paginator => self
          subscriber.render_without_logging = false

          ret
        else
          super @window_options.merge :paginator => self
        end
      end

      # Wraps a "page number" and provides some utility methods
      class PageProxy
        include Comparable

        def initialize(options, page, last, left_decade = [], right_decade = []) #:nodoc:
          @options, @page, @last = options, page, last
          @left_decade = left_decade
          @right_decade = right_decade
        end

        # the page number
        def number
          @page
        end

        # current page or not
        def current?
          @page == @options[:current_page]
        end

        # the first page or not
        def first?
          @page == 1
        end

        # the last page or not
        def last?
          @page == @options[:total_pages]
        end

        # the previous page or not
        def prev?
          @page == @options[:current_page] - 1
        end

        # the next page or not
        def next?
          @page == @options[:current_page] + 1
        end

        # within the left outer window or not
        def left_outer?
          @page <= @options[:left] && !left_decade?
        end

        # within the right outer window or not
        def right_outer?
          @options[:total_pages] - @page < @options[:right] && !right_decade?
        end

        # inside the inner window or not
        def inside_window?
          (@options[:current_page] - @page).abs <= @options[:window]
        end

        # within the left decade
        def left_decade?
          @left_decade.include? @page 
        end

        # within the left decade
        def right_decade?
          @right_decade.include? @page 
        end

        # The last rendered tag was "truncated" or not
        def was_truncated?
          @last.is_a? Gap
        end

        def to_i
          number
        end

        def to_s
          number.to_s
        end

        def +(other)
          to_i + other.to_i
        end

        def -(other)
          to_i - other.to_i
        end

        def <=>(other)
          to_i <=> other.to_i
        end
      end
    end
  end
end
