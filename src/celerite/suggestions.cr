module Celerite
  # `Did you mean?` suggestions for unknown switches, mirroring Thor 1.5's
  # did_you_mean integration (Ruby 4.0): SpellChecker#corrections applies
  # Jaro-Winkler (threshold 0.834 for inputs longer than 3, 0.77 otherwise),
  # then filters by Levenshtein <= ceil(length * 0.25), sorts by Jaro-Winkler
  # descending and caps at MAX_VARIATIONS. Formatter prints the first entry
  # after two spaces and indents the rest by 15 spaces.
  module Suggestions
    MAX_VARIATIONS = 5
    INDENT         = " " * 15

    # Mirrors `DidYouMean::SpellChecker#correct`: every comparison (Jaro-Winkler
    # threshold, the Levenshtein budget and the misspell fallback) uses the full
    # switch text including the leading dashes, normalised with `downcase` and
    # `delete("@")`. Stripping the dashes first changes both the similarity and
    # the edit budget, which is why `--lockfil` must still suggest `--local`
    # (three edits inside ceil(9 * 0.25)) while `--jbos` must not suggest
    # `--verbose` (four edits, budget two).
    def self.for(input : String, dictionary : Array(String)) : Array(String)
      probe = input.split("=", 2)[0]
      normalized_input = normalize(probe)
      threshold = normalized_input.size > 3 ? 0.834 : 0.77

      words = dictionary.uniq.select do |word|
        jaro_winkler(normalize(word), normalized_input) >= threshold
      end
      words.reject! { |word| probe == word }
      words.sort_by! { |word| jaro_winkler(word, normalized_input) }
      words.reverse!

      budget = (normalized_input.size * 0.25).ceil.to_i
      corrections = words.select { |word| levenshtein(normalize(word), normalized_input) <= budget }

      # did_you_mean's misspell pass: when the edit-distance filter drops every
      # candidate, keep the closest one that is still "closer than unrelated"
      # (`--frozen` -> `--force` comes from here, not from the edit budget).
      if corrections.empty?
        corrections = words.select do |word|
          normalized = normalize(word)
          shortest = {normalized_input.size, normalized.size}.min
          levenshtein(normalized, normalized_input) < shortest
        end.first(1)
      end

      corrections.first(MAX_VARIATIONS)
    end

    private def self.normalize(value : String) : String
      value.downcase.delete('@')
    end

    def self.message(unknown : String, dictionary : Array(String)) : String?
      picks = self.for(unknown.split("=", 2)[0], dictionary)
      return nil if picks.empty?
      first = picks.first
      rest = picks.skip(1)
      return "Did you mean?  \"#{first}\"" if rest.empty?

      "Did you mean?  \"#{first}\"\n" + rest.map { |pick| "#{INDENT}\"#{pick}\"" }.join("\n")
    end

    # Jaro similarity with the Winkler prefix boost (did_you_mean computes
    # `JaroWinkler.distance` as this similarity, higher is closer).
    def self.jaro_winkler(a : String, b : String) : Float64
      return 1.0 if a == b
      return 0.0 if a.empty? || b.empty?

      a_chars = a.chars
      b_chars = b.chars
      match_distance = {a_chars.size, b_chars.size}.max // 2 - 1
      match_distance = 0 if match_distance < 0
      a_matched = Array(Bool).new(a_chars.size, false)
      b_matched = Array(Bool).new(b_chars.size, false)
      matches = 0
      a_chars.each_with_index do |char, index|
        start = index - match_distance
        start = 0 if start < 0
        finish = index + match_distance
        finish = b_chars.size - 1 if finish >= b_chars.size
        (start..finish).each do |cursor|
          next if b_matched[cursor]
          next unless b_chars[cursor] == char
          a_matched[index] = true
          b_matched[cursor] = true
          matches += 1
          break
        end
      end
      return 0.0 if matches.zero?

      transpositions = 0
      cursor = 0
      a_chars.each_with_index do |char, index|
        next unless a_matched[index]
        while cursor < b_chars.size && !b_matched[cursor]
          cursor += 1
        end
        break if cursor >= b_chars.size
        transpositions += 1 if char != b_chars[cursor]
        cursor += 1
      end
      transpositions //= 2

      m = matches.to_f
      jaro = (m / a_chars.size + m / b_chars.size + (m - transpositions) / m) / 3.0
      prefix = 0
      [4, {a_chars.size, b_chars.size}.min].min.times do |index|
        break unless a_chars[index] == b_chars[index]
        prefix += 1
      end
      jaro + prefix * 0.1 * (1.0 - jaro)
    end

    def self.levenshtein(a : String, b : String) : Int32
      return b.size if a.empty?
      return a.size if b.empty?
      previous = (0..b.size).to_a
      current = Array(Int32).new(b.size + 1, 0)
      a.each_char.with_index(1) do |a_char, i|
        current[0] = i
        b.each_char.with_index(1) do |b_char, j|
          cost = a_char == b_char ? 0 : 1
          deletion = previous[j] + 1
          insertion = current[j - 1] + 1
          substitution = previous[j - 1] + cost
          current[j] = {deletion, insertion, substitution}.min
        end
        previous, current = current, previous
      end
      previous[b.size]
    end
  end
end
