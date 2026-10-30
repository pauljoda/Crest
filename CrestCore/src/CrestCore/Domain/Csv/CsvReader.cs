using System.Globalization;
using System.Text;

namespace CrestCore.Domain;

/// Reads comma-separated text as RFC 4180 spells it: fields separated by
/// commas, rows by a line feed, a carriage return or both, and a field in
/// double quotes may hold commas, line breaks and doubled quotes. A line
/// break inside quotes reads as one line feed. A quote that opens a field
/// anywhere but its start, text after a closing quote, or a quote left open
/// is malformed. A last row needs no line break after it.
///
/// Reading stops at the first limit `Limits` sets, so a hostile file costs no
/// more than the limits allow.
public sealed class CsvReader {
    #region Static Variables

    /// The most UTF-16 code units a character, as a person counts one, may
    /// take. A field holding more code units than its character limit times
    /// this is too large whatever it spells, so it is refused as it is read
    /// and its characters are counted once, when it ends, never at each unit.
    private const int MaximumUnitsPerCharacter = 16;

    #endregion

    #region Variables

    /// The most a text may hold.
    public CsvLimits Limits { get; }

    #endregion

    #region Constructors

    public CsvReader(CsvLimits limits) {
        ArgumentNullException.ThrowIfNull(limits);
        Limits = limits;
    }

    #endregion

    #region Actions - Reading

    /// The rows `text` holds, each a list of its fields. Throws
    /// `CsvException` naming the first rule the text breaks.
    public IReadOnlyList<IReadOnlyList<string>> Read(string text) {
        ArgumentNullException.ThrowIfNull(text);
        var rows = new List<IReadOnlyList<string>>();
        var row = new List<string>();
        var field = new StringBuilder();
        bool inQuotes = false, afterClosingQuote = false, fieldStarted = false;

        void EndField() {
            string value = field.ToString();
            CheckCharacters(value);
            row.Add(value);
            field.Clear();
            fieldStarted = false;
            afterClosingQuote = false;
            if (row.Count > Limits.MaximumColumns) throw new CsvException(CsvFault.TooManyColumns);
        }

        void EndRow() {
            EndField();
            rows.Add(row);
            row = [];
            if (rows.Count > Limits.MaximumRows) throw new CsvException(CsvFault.TooManyRows);
        }

        for (int index = 0; index < text.Length; index++) {
            char character = text[index];
            bool breaksLine = character is '\n' or '\r';
            // A carriage return and the line feed after it are one line break.
            if (character == '\r' && index + 1 < text.Length && text[index + 1] == '\n') index++;

            if (inQuotes) {
                if (character == '"') {
                    if (index + 1 < text.Length && text[index + 1] == '"') {
                        field.Append('"');
                        index++;
                    } else {
                        inQuotes = false;
                        afterClosingQuote = true;
                    }
                } else {
                    field.Append(breaksLine ? '\n' : character);
                }
                CheckUnits(field);
                continue;
            }
            if (afterClosingQuote) {
                if (character == ',') EndField();
                else if (breaksLine) EndRow();
                else throw new CsvException(CsvFault.Malformed);
                continue;
            }
            if (character == '"') {
                if (fieldStarted || field.Length > 0) throw new CsvException(CsvFault.Malformed);
                inQuotes = true;
                fieldStarted = true;
            } else if (character == ',') {
                EndField();
            } else if (breaksLine) {
                EndRow();
            } else {
                field.Append(character);
                fieldStarted = true;
                CheckUnits(field);
            }
        }
        if (inQuotes) {
            CheckCharacters(field.ToString());
            throw new CsvException(CsvFault.Malformed);
        }
        if (fieldStarted || afterClosingQuote || field.Length > 0 || row.Count > 0) EndRow();
        return rows;
    }

    /// Throws `CsvException` when `field`, still being read, holds more
    /// UTF-16 code units than any field within its character limit can.
    private void CheckUnits(StringBuilder field) {
        if (field.Length > (long)Limits.MaximumFieldCharacters * MaximumUnitsPerCharacter)
            throw new CsvException(CsvFault.FieldTooLarge);
    }

    /// Throws `CsvException` when the finished `field` holds more characters,
    /// as a person counts them, than a field may.
    private void CheckCharacters(string field) {
        if (field.Length <= Limits.MaximumFieldCharacters) return;
        if (new StringInfo(field).LengthInTextElements > Limits.MaximumFieldCharacters)
            throw new CsvException(CsvFault.FieldTooLarge);
    }

    #endregion
}

/// The most rows, fields in a row and characters in a field a CSV text may
/// hold. A field's characters are counted as a person counts them, once the
/// field ends; while it is read, each may take at most sixteen code units.
public sealed record CsvLimits(int MaximumRows, int MaximumColumns, int MaximumFieldCharacters);

/// The first rule a CSV text breaks.
public enum CsvFault {
    /// A quote opens a field anywhere but its start, text follows a closing
    /// quote, or a quote is left open.
    Malformed,
    /// It holds more rows than its limits allow.
    TooManyRows,
    /// A row holds more fields than its limits allow.
    TooManyColumns,
    /// A field holds more characters than its limits allow.
    FieldTooLarge
}

/// A CSV text breaks `Fault`.
public sealed class CsvException(CsvFault fault) : Exception(fault.ToString()) {
    #region Variables

    public CsvFault Fault { get; } = fault;

    #endregion
}
