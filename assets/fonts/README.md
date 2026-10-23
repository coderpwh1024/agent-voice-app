# Studio Serif

A locally bundled, static 400-weight subset of Noto Serif SC, used only for the
shared app wordmarks and fixed editorial headings. Body text and user-generated
video titles use the system sans-serif font. The font works without a network
connection and is shared by the voice, account, journal, memory and video modules.

Source: https://github.com/google/fonts/tree/main/ofl/notoserifsc
Original font: `NotoSerifSC[wght].ttf` (downloaded 2026-10-23).
License: SIL Open Font License 1.1, included in `OFL-NotoSerifSC.txt`.

The font was instantiated at `wght=400` and subset with fontTools to the
characters used in the app UI source. The modified font was renamed
Studio Serif. Add heading glyphs to the subset when changing fixed headings;
do not use this subset for arbitrary user text.
