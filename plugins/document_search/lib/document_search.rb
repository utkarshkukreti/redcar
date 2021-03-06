require 'strscan'
require "document_search/replace_command"
require "document_search/replace_all_command"
require "document_search/replace_next_command"
require "document_search/search_and_replace"

module DocumentSearch
  def self.menus
    Redcar::Menu::Builder.build do
      sub_menu "Edit" do
        sub_menu "Search", :priority => 50 do
          item "Document Search",    SearchForwardCommand
          item "Repeat Last Search", RepeatPreviousSearchForwardCommand
          item "Search and Replace", SearchAndReplaceCommand
        end
        separator
      end
    end
  end

  def self.toolbars
    Redcar::ToolBar::Builder.build do
      item "Search Document", :command => DocumentSearch::SearchForwardCommand, :icon => File.join(Redcar::ICONS_DIRECTORY, "magnifier.png"), :barname => :edit
      item "Repeat Last Search", :command => DocumentSearch::RepeatPreviousSearchForwardCommand, :icon => File.join(Redcar::ICONS_DIRECTORY, "magnifier--arrow.png"), :barname => :edit
    end
  end

  class SearchSpeedbar < Redcar::Speedbar
    class << self
      attr_accessor :previous_query
      attr_accessor :previous_is_regex
      attr_accessor :previous_match_case
    end

    attr_accessor :initial_query

    def doc
      win = Redcar.app.focussed_window
      tab = win.focussed_notebook_tab
      tab.document if tab
    end

    def after_draw
      SearchSpeedbar.previous_query ||= ""
      self.query.value = @initial_query || SearchSpeedbar.previous_query
      self.is_regex.value = SearchSpeedbar.previous_is_regex
      self.match_case.value = SearchSpeedbar.previous_match_case
      self.query.edit_view.document.select_all
    end

    label :label, "Search:"
    textbox :query do |value|
      if doc
        set_offset
        start_search
      end
    end

    toggle :is_regex, 'Regex', nil, false do |v|
      # v is true or false
      SearchSpeedbar.previous_is_regex = v
      update_search
    end

    toggle :match_case, 'Match case', nil, false do |v|
      SearchSpeedbar.previous_match_case = v
      update_search
    end

    button :search, "Search", "Return" do
      if doc
        @offset = nil
        doc.set_selection_range(doc.cursor_offset,0)
        start_search
      end
    end

    def start_search
      if doc
        SearchSpeedbar.previous_query = self.query.value
        SearchSpeedbar.previous_match_case = self.match_case.value
        SearchSpeedbar.previous_is_regex = self.is_regex.value
        success = SearchSpeedbar.repeat_query
      end
    end

    def update_search
      if doc and self.query.value and self.query.value != ""
        set_offset
        SearchSpeedbar.previous_query = self.query.value
        SearchSpeedbar.repeat_query
      end
    end

    def set_offset
      @offset = doc.cursor_offset unless @offset
      if doc.selection?
        if doc.selection_offset != @offset + doc.selected_text.length
          @offset = [doc.cursor_offset, doc.selection_offset].min
        end
      else
        @offset = doc.cursor_offset
      end
      doc.cursor_offset = @offset
    end

    def self.repeat_query
      current_query = @previous_query
      if !@previous_is_regex
        current_query = Regexp.escape(current_query)
      end
      cmd = FindNextRegex.new(Regexp.new(current_query, !@previous_match_case), true)
      cmd.run_in_focussed_tab_edit_view
    end
  end

  class SearchForwardCommand < Redcar::EditTabCommand

    def execute
      @speedbar = SearchSpeedbar.new
      if doc.selection?
        @speedbar.initial_query = doc.selected_text
      end
      win.open_speedbar(@speedbar)
    end
  end

  class RepeatPreviousSearchForwardCommand < Redcar::EditTabCommand
    def execute
      SearchSpeedbar.repeat_query
    end
  end

  class SearchAndReplaceCommand < Redcar::EditTabCommand
    def execute
      @speedbar = SearchAndReplaceSpeedbar.new
      if doc.selection?
        @speedbar.initial_query = doc.selected_text
      end
      win.open_speedbar(@speedbar)
    end
  end

  class FindNextRegex < Redcar::DocumentCommand
    def initialize(re, wrap=nil)
      @re = re
      @wrap = wrap
    end

    def to_s
      "<#{self.class}: @re:#{@re.inspect} wrap:#{!!@wrap}>"
    end

    def execute
      position = doc.cursor_offset
      sc       = StringScanner.new(doc.get_all_text)
      sc.pos   = position
      sc.scan_until(@re)

      if @wrap and !sc.matched?
        # No match was found in the remainder of the document, search from beginning
        sc.reset
        sc.scan_until(@re)
      end

      if sc.matched?
        endoff   = sc.pos
        startoff = sc.pos - sc.matched_size
        line     = doc.line_at_offset(startoff)
        lineoff  = startoff - doc.offset_at_line(line)
        if lineoff < doc.smallest_visible_horizontal_index
          horiz = lineoff
        else
          horiz = endoff - doc.offset_at_line(line)
        end
        doc.set_selection_range(sc.pos, sc.pos - sc.matched_size)
        doc.scroll_to_line(line)
        doc.scroll_to_horizontal_offset(horiz) if horiz
        return true
      end
      false
    end
  end
end