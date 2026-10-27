'use strict';

// Read literal tools.update_plan({...}) calls inside Codex code-mode wrappers.
// This is a bounded lexer, NEVER eval/vm/Function. Dynamic or malformed arguments
// stay unsupported; strings/comments/templates cannot masquerade as calls.
function lex(source) {
  if (typeof source !== 'string' || Buffer.byteLength(source) > 1024 * 1024) return null;
  const tokens = []; let i = 0;
  while (i < source.length && tokens.length < 65536) {
    const c = source[i];
    if (/\s/.test(c)) { i++; continue; }
    if (source.startsWith('//', i)) { i = source.indexOf('\n', i + 2); if (i < 0) break; continue; }
    if (source.startsWith('/*', i)) { const end = source.indexOf('*/', i + 2); if (end < 0) return null; i = end + 2; continue; }
    if (['"', "'", '`'].includes(c)) {
      const quote = c; let value = '', closed = false; i++;
      while (i < source.length) {
        let ch = source[i++];
        if (ch === quote) { closed = true; break; }
        if (ch === '\\') {
          if (i >= source.length) return null;
          const escape = source[i++];
          if (escape === 'u' || escape === 'x') {
            const count = escape === 'u' ? 4 : 2, code = source.slice(i, i + count);
            if (code.length !== count || !/^[a-f0-9]+$/i.test(code)) return null;
            value += String.fromCharCode(parseInt(code, 16)); i += count;
          } else value += ({ n: '\n', r: '\r', t: '\t', b: '\b', f: '\f' })[escape] ?? escape;
        } else value += ch;
      }
      if (!closed) return null;
      tokens.push({ type: quote === '`' ? 'template' : 'string', value }); continue;
    }
    if (c === '/') {
      // Ambiguous regex/division is skipped conservatively to the next slash or
      // line break, rather than interpreting a regex's contents as JavaScript.
      i++;
      while (i < source.length && source[i] !== '\n') { if (source[i] === '\\') { i += 2; continue; } if (source[i++] === '/') break; }
      tokens.push({ type: 'opaque', value: '/' }); continue;
    }
    const word = /^[A-Za-z_$][\w$]*/.exec(source.slice(i));
    if (word) { tokens.push({ type: 'identifier', value: word[0] }); i += word[0].length; continue; }
    const number = /^-?\d+(?:\.\d+)?/.exec(source.slice(i));
    if (number) { tokens.push({ type: 'number', value: Number(number[0]) }); i += number[0].length; continue; }
    tokens.push({ type: 'punctuation', value: c }); i++;
  }
  return i < source.length ? null : tokens;
}
function literal(tokens, cursor, depth = 0) {
  if (depth > 32) return null;
  const token = tokens[cursor]; if (!token) return null;
  if (['string', 'number'].includes(token.type)) return { value: token.value, end: cursor + 1 };
  if (token.type === 'identifier' && ['true', 'false', 'null'].includes(token.value)) return { value: token.value === 'null' ? null : token.value === 'true', end: cursor + 1 };
  if (token.value === '[') {
    const value = []; cursor++;
    while (tokens[cursor]?.value !== ']') {
      if (value.length >= 128) return null;
      const entry = literal(tokens, cursor, depth + 1); if (!entry) return null;
      value.push(entry.value); cursor = entry.end;
      if (tokens[cursor]?.value === ',') cursor++; else if (tokens[cursor]?.value !== ']') return null;
    }
    return { value, end: cursor + 1 };
  }
  if (token.value === '{') {
    const value = Object.create(null); let count = 0; cursor++;
    while (tokens[cursor]?.value !== '}') {
      const key = tokens[cursor];
      if (!key || !['identifier', 'string'].includes(key.type) || ['__proto__', 'constructor', 'prototype'].includes(key.value) || Object.hasOwn(value, key.value) || tokens[cursor + 1]?.value !== ':' || count++ >= 128) return null;
      const entry = literal(tokens, cursor + 2, depth + 1); if (!entry) return null;
      value[key.value] = entry.value; cursor = entry.end;
      if (tokens[cursor]?.value === ',') cursor++; else if (tokens[cursor]?.value !== '}') return null;
    }
    return { value, end: cursor + 1 };
  }
  return null;
}
function wrappedPlan(source) {
  const tokens = lex(source); if (!tokens) return null;
  let result = null;
  for (let i = 0; i < tokens.length - 4; i++) {
    if (tokens[i].type !== 'identifier' || tokens[i].value !== 'tools' || tokens[i + 1].value !== '.' || tokens[i + 2].type !== 'identifier' || tokens[i + 2].value !== 'update_plan' || tokens[i + 3].value !== '(') continue;
    if (tokens[i - 1]?.value === '.') continue;
    const parsed = literal(tokens, i + 4);
    if (parsed && tokens[parsed.end]?.value === ')') { result = parsed.value; i = parsed.end; }
  }
  return result;
}
module.exports = { wrappedPlan };
