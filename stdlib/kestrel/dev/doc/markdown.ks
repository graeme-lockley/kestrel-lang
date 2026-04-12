//! CommonMark subset Markdown renderer for Kestrel doc-comment bodies.
//! Supports: paragraphs, ATX headings (h1-h6), fenced code blocks, unordered
//! and ordered lists, blockquotes, horizontal rules, and inline code, bold,
//! italic, links, and HTML entity escaping.
import * as Str from "kestrel:data/string"
import * as Lst from "kestrel:data/list"
import * as Arr from "kestrel:data/array"
import * as Lex from "kestrel:dev/parser/lexer"
import { Token, TkInt, TkFloat, TkStr, TkTemplate, TkChar, TkIdent, TkUpper, TkKw, TkOp, TkPunct, TkWs, TkLineComment, TkBlockComment, TkEof } from "kestrel:dev/parser/token"

// ── HTML escaping ─────────────────────────────────────────────────────────────

fun escapeHtml(s: String): String =
  Str.replace(">", "&gt;", Str.replace("<", "&lt;", Str.replace("&", "&amp;", s)))

fun escapeAttr(s: String): String =
  Str.replace("\"", "&quot;", escapeHtml(s))

fun span(cls: String, text: String): String =
  "<span class=\"${cls}\">${escapeHtml(text)}</span>"

fun renderKestrelToken(tok: Token): String =
  match (tok.kind) {
    TkKw           => span("tok-kw", tok.text),
    TkUpper        => span("tok-type", tok.text),
    TkInt          => span("tok-lit", tok.text),
    TkFloat        => span("tok-lit", tok.text),
    TkStr          => span("tok-lit", tok.text),
    TkTemplate(_)  => span("tok-lit", tok.text),
    TkChar         => span("tok-lit", tok.text),
    TkLineComment  => span("tok-comment", tok.text),
    TkBlockComment => span("tok-comment", tok.text),
    TkOp           => span("tok-op", tok.text),
    TkPunct        => span("tok-punct", tok.text),
    TkIdent        => escapeHtml(tok.text),
    TkWs           => escapeHtml(tok.text),
    TkEof          => ""
  }

fun renderKestrelCode(code: String): String =
  Str.join("", Lst.map(Lex.lex(code), (tok: Token) => renderKestrelToken(tok)))

fun isKestrelFence(lang: String): Bool = {
  val l = Str.toLower(Str.trim(lang))
  l == "kestrel" | l == "ks"
}

// ── Inline rendering helpers ──────────────────────────────────────────────────

// Return the minimum non-negative integer from a and b; -1 represents "absent".
fun minPos(a: Int, b: Int): Int =
  if (a == -1) b
  else if (b == -1) a
  else if (a <= b) a else b

// Scan s[pos..n) for the earliest special inline marker.
fun firstInlineMarker(s: String, pos: Int, n: Int): Int = {
  val tick   = Str.indexOfFrom(s, "`", pos)
  val boldS  = Str.indexOfFrom(s, "**", pos)
  val boldU  = Str.indexOfFrom(s, "__", pos)
  val link   = Str.indexOfFrom(s, "[", pos)
  val amp    = Str.indexOfFrom(s, "&", pos)
  val lt     = Str.indexOfFrom(s, "<", pos)
  val gt     = Str.indexOfFrom(s, ">", pos)
  val starA  = Str.indexOfFrom(s, "*", pos)
  val italicS =
    if (starA != -1 & starA == boldS) Str.indexOfFrom(s, "*", boldS + 2)
    else starA
  val undA   = Str.indexOfFrom(s, "_", pos)
  val italicU =
    if (undA != -1 & undA == boldU) Str.indexOfFrom(s, "_", boldU + 2)
    else undA
  minPos(tick, minPos(boldS, minPos(boldU, minPos(italicS, minPos(italicU, minPos(link, minPos(amp, minPos(lt, gt))))))))
}

export fun renderInline(s: String): String = renderInlineRec(s, 0, Str.length(s))

fun renderInlineRec(s: String, pos: Int, n: Int): String =
  if (pos >= n) ""
  else {
    val first = firstInlineMarker(s, pos, n)
    if (first == -1) Str.slice(s, pos, n)
    else {
      val prefix = Str.slice(s, pos, first)
      val tick   = Str.indexOfFrom(s, "`", pos)
      val boldS  = Str.indexOfFrom(s, "**", pos)
      val boldU  = Str.indexOfFrom(s, "__", pos)
      val amp    = Str.indexOfFrom(s, "&", pos)
      val lt     = Str.indexOfFrom(s, "<", pos)
      val gt     = Str.indexOfFrom(s, ">", pos)
      val link   = Str.indexOfFrom(s, "[", pos)
      val starA  = Str.indexOfFrom(s, "*", pos)
      val italicS =
        if (starA != -1 & starA == boldS) Str.indexOfFrom(s, "*", boldS + 2)
        else starA
      val undA   = Str.indexOfFrom(s, "_", pos)
      val italicU =
        if (undA != -1 & undA == boldU) Str.indexOfFrom(s, "_", boldU + 2)
        else undA
      if (first == amp) "${prefix}&amp;${renderInlineRec(s, first + 1, n)}"
      else if (first == lt) "${prefix}&lt;${renderInlineRec(s, first + 1, n)}"
      else if (first == gt) "${prefix}&gt;${renderInlineRec(s, first + 1, n)}"
      else if (first == tick) {
        val closePos = Str.indexOfFrom(s, "`", first + 1)
        if (closePos == -1) "${prefix}`${renderInlineRec(s, first + 1, n)}"
        else {
          val code = Str.slice(s, first + 1, closePos)
          "${prefix}<code>${escapeHtml(code)}</code>${renderInlineRec(s, closePos + 1, n)}"
        }
      }
      else if (first == boldS) {
        val sub = Str.slice(s, first + 2, n)
        val closeOff = Str.indexOf(sub, "**")
        if (closeOff == -1) "${prefix}**${renderInlineRec(s, first + 2, n)}"
        else {
          val content = Str.slice(s, first + 2, first + 2 + closeOff)
          "${prefix}<strong>${renderInline(content)}</strong>${renderInlineRec(s, first + 2 + closeOff + 2, n)}"
        }
      }
      else if (first == boldU) {
        val sub = Str.slice(s, first + 2, n)
        val closeOff = Str.indexOf(sub, "__")
        if (closeOff == -1) "${prefix}__${renderInlineRec(s, first + 2, n)}"
        else {
          val content = Str.slice(s, first + 2, first + 2 + closeOff)
          "${prefix}<strong>${renderInline(content)}</strong>${renderInlineRec(s, first + 2 + closeOff + 2, n)}"
        }
      }
      else if (first == italicS) {
        val sub = Str.slice(s, first + 1, n)
        val closeOff = Str.indexOf(sub, "*")
        if (closeOff == -1) "${prefix}*${renderInlineRec(s, first + 1, n)}"
        else {
          val content = Str.slice(s, first + 1, first + 1 + closeOff)
          "${prefix}<em>${renderInline(content)}</em>${renderInlineRec(s, first + 1 + closeOff + 1, n)}"
        }
      }
      else if (first == italicU) {
        val sub = Str.slice(s, first + 1, n)
        val closeOff = Str.indexOf(sub, "_")
        if (closeOff == -1) "${prefix}_${renderInlineRec(s, first + 1, n)}"
        else {
          val content = Str.slice(s, first + 1, first + 1 + closeOff)
          "${prefix}<em>${renderInline(content)}</em>${renderInlineRec(s, first + 1 + closeOff + 1, n)}"
        }
      }
      else if (first == link) {
        val rbIdx = Str.indexOfFrom(s, "](", first + 1)
        if (rbIdx == -1) "${prefix}[${renderInlineRec(s, first + 1, n)}"
        else {
          val rpIdx = Str.indexOfFrom(s, ")", rbIdx + 2)
          if (rpIdx == -1) "${prefix}[${renderInlineRec(s, first + 1, n)}"
          else {
            val label = Str.slice(s, first + 1, rbIdx)
            val url   = Str.slice(s, rbIdx + 2, rpIdx)
            "${prefix}<a href=\"${escapeAttr(url)}\">${renderInline(label)}</a>${renderInlineRec(s, rpIdx + 1, n)}"
          }
        }
      }
      else "${prefix}${renderInlineRec(s, first + 1, n)}"
    }
  }

// ── Block rendering helpers ───────────────────────────────────────────────────

// Returns 1–6 for ATX headings, 0 if not a heading.
fun headingLevel(line: String): Int =
  if      (Str.startsWith("###### ", line)) 6
  else if (Str.startsWith("##### ",  line)) 5
  else if (Str.startsWith("#### ",   line)) 4
  else if (Str.startsWith("### ",    line)) 3
  else if (Str.startsWith("## ",     line)) 2
  else if (Str.startsWith("# ",      line)) 1
  else 0

fun renderHeadingLine(line: String): String = {
  val lvl  = headingLevel(line)
  val text = Str.trim(Str.dropLeft(line, lvl + 1))
  val tag  = if (lvl == 1) "h1" else if (lvl == 2) "h2" else if (lvl == 3) "h3"
             else if (lvl == 4) "h4" else if (lvl == 5) "h5" else "h6"
  "<${tag}>${renderInline(text)}</${tag}>\n"
}

fun isHRule(line: String): Bool = {
  val t = Str.trim(line)
  t == "---" | t == "***" | t == "___"
}

fun isUlItem(line: String): Bool =
  Str.startsWith("- ", line) | Str.startsWith("* ", line)

fun ulItemContent(line: String): String = Str.dropLeft(line, 2)

fun isOlItem(line: String): Bool = {
  val n = Str.length(line)
  if (n < 3) False
  else {
    val dotPos = Str.indexOf(line, ". ")
    if (dotPos <= 0) False
    else {
      val c0 = Str.codePointAt(line, 0)
      c0 >= 48 & c0 <= 57
    }
  }
}

fun olItemContent(line: String): String = {
  val dotPos = Str.indexOf(line, ". ")
  if (dotPos == -1) line else Str.dropLeft(line, dotPos + 2)
}

fun isBlockquoteLine(line: String): Bool =
  Str.startsWith(">", line)

fun bqLineContent(line: String): String =
  if (Str.startsWith("> ", line)) Str.dropLeft(line, 2)
  else Str.dropLeft(line, 1)

fun isFenceStart(line: String): Bool =
  Str.startsWith("```", Str.trim(line))

fun fenceLang(line: String): String =
  Str.trim(Str.dropLeft(Str.trim(line), 3))

// Flush accumulated paragraph text: wrap in <p> if non-empty.
fun flushPara(para: String): String =
  if (Str.isEmpty(Str.trim(para))) ""
  else "<p>${renderInline(Str.trim(para))}</p>\n"

// ── Main block renderer ───────────────────────────────────────────────────────

fun renderLinesArr(arr: Array<String>, n: Int): String = {
  var i      = 0
  var out    = ""
  var para   = ""
  var inCode   = False
  var codeLang = ""
  var codeBody = ""
  var inUl = False
  var inOl = False

  while (i < n) {
    val line = Arr.get(arr, i)

    if (inCode) {
      if (isFenceStart(line)) {
        val langNorm = Str.toLower(Str.trim(codeLang))
        val langAttr =
          if (Str.isEmpty(langNorm)) ""
          else " class=\"language-${escapeAttr(langNorm)}\""
        val bodyHtml =
          if (isKestrelFence(langNorm)) renderKestrelCode(codeBody)
          else escapeHtml(codeBody)
        out      := "${out}<pre><code${langAttr}>${bodyHtml}</code></pre>\n"
        inCode   := False
        codeLang := ""
        codeBody := ""
      } else {
        codeBody := "${codeBody}${line}\n"
      }
    } else if (Str.isEmpty(Str.trim(line))) {
      out  := "${out}${flushPara(para)}"
      para := ""
      if (inUl) { out := "${out}</ul>\n"; inUl := False }
      if (inOl) { out := "${out}</ol>\n"; inOl := False }
    } else if (isFenceStart(line)) {
      out      := "${out}${flushPara(para)}"
      para     := ""
      if (inUl) { out := "${out}</ul>\n"; inUl := False }
      if (inOl) { out := "${out}</ol>\n"; inOl := False }
      codeLang := fenceLang(line)
      inCode   := True
    } else if (headingLevel(line) > 0) {
      out  := "${out}${flushPara(para)}"
      para := ""
      if (inUl) { out := "${out}</ul>\n"; inUl := False }
      if (inOl) { out := "${out}</ol>\n"; inOl := False }
      out  := "${out}${renderHeadingLine(line)}"
    } else if (isHRule(line)) {
      out  := "${out}${flushPara(para)}"
      para := ""
      if (inUl) { out := "${out}</ul>\n"; inUl := False }
      if (inOl) { out := "${out}</ol>\n"; inOl := False }
      out  := "${out}<hr />\n"
    } else if (isBlockquoteLine(line)) {
      out  := "${out}${flushPara(para)}"
      para := ""
      if (inUl) { out := "${out}</ul>\n"; inUl := False }
      if (inOl) { out := "${out}</ol>\n"; inOl := False }
      // Treat each blockquote line as its own <blockquote> paragraph for simplicity.
      out := "${out}<blockquote><p>${renderInline(bqLineContent(line))}</p></blockquote>\n"
    } else if (isUlItem(line)) {
      out  := "${out}${flushPara(para)}"
      para := ""
      if (inOl) { out := "${out}</ol>\n"; inOl := False }
      if (!inUl) { out := "${out}<ul>\n"; inUl := True }
      out := "${out}<li>${renderInline(ulItemContent(line))}</li>\n"
    } else if (isOlItem(line)) {
      out  := "${out}${flushPara(para)}"
      para := ""
      if (inUl) { out := "${out}</ul>\n"; inUl := False }
      if (!inOl) { out := "${out}<ol>\n"; inOl := True }
      out := "${out}<li>${renderInline(olItemContent(line))}</li>\n"
    } else {
      if (inUl) { out := "${out}</ul>\n"; inUl := False }
      if (inOl) { out := "${out}</ol>\n"; inOl := False }
      if (Str.isEmpty(para)) { para := line }
      else { para := "${para} ${line}" }
    }
    i := i + 1
  }

  out := "${out}${flushPara(para)}"
  if (inUl) { out := "${out}</ul>\n"; () } else ()
  if (inOl) { out := "${out}</ol>\n"; () } else ()
  if (inCode) {
    val langNorm = Str.toLower(Str.trim(codeLang))
    val langAttr =
      if (Str.isEmpty(langNorm)) ""
      else " class=\"language-${escapeAttr(langNorm)}\""
    val bodyHtml =
      if (isKestrelFence(langNorm)) renderKestrelCode(codeBody)
      else escapeHtml(codeBody)
    out := "${out}<pre><code${langAttr}>${bodyHtml}</code></pre>\n";
    ()
  } else ()
  out
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Render a CommonMark subset Markdown string to an HTML fragment.
/// Supports paragraphs, headings (h1–h6), fenced code blocks, unordered and
/// ordered lists, blockquotes, horizontal rules, and inline code, bold,
/// italic, links, and HTML entity escaping.
export fun render(md: String): String = {
  val lines = Str.lines(md)
  val arr   = Arr.fromList(lines)
  renderLinesArr(arr, Arr.length(arr))
}


