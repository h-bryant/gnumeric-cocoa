// Text export options over the engine's per-workbook GnmStfExport, set
// the way dialog-stf-export.c's stf_export_dialog_finish sets it.
#import "GnmPrivate.h"
#include <stf-export.h>
#include <gsf/gsf-output-csv.h>

@implementation GnmTextExportOptions

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _sheets = @[];
    _lineEnding = GnmTextLineEndingUnix;
    _separator = @",";
    _quoting = GnmTextQuotingAutomatic;
    _quoteCharacter = @"\"";
    _characterEncoding = nil;
    _locale = nil;
    _unknownCharacters = GnmTextUnknownCharactersEscape;
    _format = GnmTextFormatAutomatic;
    _exportsFormulas = NO;
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    GnmTextExportOptions *copy = [[GnmTextExportOptions allocWithZone:zone] init];
    copy.sheets = _sheets;
    copy.lineEnding = _lineEnding;
    copy.separator = _separator;
    copy.quoting = _quoting;
    copy.quoteCharacter = _quoteCharacter;
    copy.characterEncoding = _characterEncoding;
    copy.locale = _locale;
    copy.unknownCharacters = _unknownCharacters;
    copy.format = _format;
    copy.exportsFormulas = _exportsFormulas;
    return copy;
}

+ (BOOL)canTransliterate
{
    return gnm_stf_export_can_transliterate ();
}

@end

static NSString *
string_or_nil (const char *s)
{
    return s && *s ? [NSString stringWithUTF8String:s] : nil;
}

static const char *
eol_for (GnmTextLineEnding ending)
{
    switch (ending) {
    case GnmTextLineEndingMacintosh: return "\r";
    case GnmTextLineEndingWindows: return "\r\n";
    case GnmTextLineEndingUnix:
    default: return "\n";
    }
}

static GnmTextLineEnding
ending_for (const char *eol)
{
    if (eol && strcmp (eol, "\r") == 0)
        return GnmTextLineEndingMacintosh;
    if (eol && strcmp (eol, "\r\n") == 0)
        return GnmTextLineEndingWindows;
    return GnmTextLineEndingUnix;
}

@implementation GnmWorkbook (TextExport)

- (GnmTextExportOptions *)textExportOptions
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GnmStfExport *stfe = gnm_stf_get_stfe (G_OBJECT (self.engineWorkbook));
    GnmTextExportOptions *o = [[GnmTextExportOptions alloc] init];
    char *eol = NULL, *separator = NULL, *quote = NULL, *charset = NULL, *locale = NULL;
    GsfOutputCsvQuotingMode quoting = GSF_OUTPUT_CSV_QUOTING_MODE_AUTO;
    GnmStfTransliterateMode transliterate = GNM_STF_TRANSLITERATE_MODE_ESCAPE;
    GnmStfFormatMode format = GNM_STF_FORMAT_AUTO;
    gboolean formulas = FALSE;
    g_object_get (stfe, "eol", &eol, "separator", &separator, "quote", &quote, "charset", &charset, "locale", &locale,
                  "quoting-mode", &quoting, "transliterate-mode", &transliterate, "format", &format, "formulas", &formulas, NULL);
    o.lineEnding = ending_for (eol);
    o.separator = separator ? [NSString stringWithUTF8String:separator] : @",";
    o.quoteCharacter = quote ? [NSString stringWithUTF8String:quote] : @"\"";
    o.characterEncoding = string_or_nil (charset);
    o.locale = string_or_nil (locale);
    switch (quoting) {
    case GSF_OUTPUT_CSV_QUOTING_MODE_ALWAYS: o.quoting = GnmTextQuotingAlways; break;
    case GSF_OUTPUT_CSV_QUOTING_MODE_NEVER: o.quoting = GnmTextQuotingNever; break;
    default: o.quoting = GnmTextQuotingAutomatic; break;
    }
    o.unknownCharacters = transliterate == GNM_STF_TRANSLITERATE_MODE_TRANS
        ? GnmTextUnknownCharactersTransliterate : GnmTextUnknownCharactersEscape;
    switch (format) {
    case GNM_STF_FORMAT_RAW: o.format = GnmTextFormatRaw; break;
    case GNM_STF_FORMAT_PRESERVE: o.format = GnmTextFormatPreserve; break;
    default: o.format = GnmTextFormatAutomatic; break;
    }
    o.exportsFormulas = formulas;
    NSMutableArray<GnmSheet *> *sheets = [NSMutableArray array];
    for (GSList *l = gnm_stf_export_options_sheet_list_get (stfe); l; l = l->next) {
        GnmSheet *wrapper = [self wrapperForEngineSheet:l->data];
        if (wrapper)
            [sheets addObject:wrapper];
    }
    o.sheets = sheets;
    g_free (eol);
    g_free (separator);
    g_free (quote);
    g_free (charset);
    g_free (locale);
    return o;
}

- (BOOL)writeToURL:(NSURL *)url textExportOptions:(GnmTextExportOptions *)options rememberAsDefault:(BOOL)remember
       adoptingURL:(BOOL)adopt error:(NSError **)error
{
    NSAssert (NSThread.isMainThread, @"engine access off the main thread");
    GOFileSaver *fs = go_file_saver_for_id ("Gnumeric_stf:stf_assistant");
    if (fs == NULL) {
        if (error)
            *error = [self.engine _errorWithCode:GnmErrorUnknownFormat description:@"The text saver is not available." collected:@[]];
        return NO;
    }
    GnmStfExport *stfe = gnm_stf_get_stfe (G_OBJECT (self.engineWorkbook));

    /* dialog-stf-export.c stf_export_dialog_finish */
    const char *eol = eol_for (options.lineEnding);
    const char *separator = options.separator.UTF8String ?: ",";
    const char *quote = options.quoteCharacter.UTF8String ?: "\"";
    const char *charset = options.characterEncoding.length ? options.characterEncoding.UTF8String : NULL;
    const char *locale = options.locale.length ? options.locale.UTF8String : NULL;
    GsfOutputCsvQuotingMode quoting;
    switch (options.quoting) {
    case GnmTextQuotingAlways: quoting = GSF_OUTPUT_CSV_QUOTING_MODE_ALWAYS; break;
    case GnmTextQuotingNever: quoting = GSF_OUTPUT_CSV_QUOTING_MODE_NEVER; break;
    default: quoting = GSF_OUTPUT_CSV_QUOTING_MODE_AUTO; break;
    }
    GnmStfTransliterateMode transliterate = options.unknownCharacters == GnmTextUnknownCharactersTransliterate
        ? GNM_STF_TRANSLITERATE_MODE_TRANS : GNM_STF_TRANSLITERATE_MODE_ESCAPE;
    GnmStfFormatMode format;
    switch (options.format) {
    case GnmTextFormatRaw: format = GNM_STF_FORMAT_RAW; break;
    case GnmTextFormatPreserve: format = GNM_STF_FORMAT_PRESERVE; break;
    default: format = GNM_STF_FORMAT_AUTO; break;
    }
    GString *triggers = g_string_new (NULL);
    if (quoting == GSF_OUTPUT_CSV_QUOTING_MODE_AUTO) {
        g_string_append (triggers, " \t");
        g_string_append (triggers, eol);
        g_string_append (triggers, quote);
        g_string_append (triggers, separator);
    }
    g_object_set (stfe,
                  "eol", eol,
                  "quote", quote,
                  "quoting-mode", quoting,
                  "quoting-triggers", triggers->str,
                  "separator", separator,
                  "transliterate-mode", transliterate,
                  "format", format,
                  "charset", charset,
                  "locale", locale,
                  "formulas", (gboolean) options.exportsFormulas,
                  NULL);
    g_string_free (triggers, TRUE);

    if (remember) {
        gnm_conf_set_stf_export_separator (separator);
        gnm_conf_set_stf_export_stringindicator (quote);
        gnm_conf_set_stf_export_terminator (eol);
        gnm_conf_set_stf_export_quoting (quoting);
        gnm_conf_set_stf_export_format (format);
        gnm_conf_set_stf_export_transliteration (transliterate == GNM_STF_TRANSLITERATE_MODE_TRANS);
        gnm_conf_set_stf_export_locale (locale ?: "");
        gnm_conf_set_stf_export_encoding (charset ?: "");
    }

    gnm_stf_export_options_sheet_list_clear (stfe);
    for (GnmSheet *sheet in options.sheets) {
        Sheet *engineSheet = sheet.engineSheet;
        if (engineSheet && sheet.workbook == self)
            gnm_stf_export_options_sheet_list_add (stfe, engineSheet);
    }
    /* An empty list makes the saver take every sheet, and clear the list
     * again afterwards. */
    return [self writeToURL:url saver:fs adoptingURL:adopt error:error];
}

@end
