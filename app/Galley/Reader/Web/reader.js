// Galley — the page's side of the bridge.
//
// Swift owns the document: it parses, diffs and decides what to show. This
// script only draws what it is given, reports where the reader is, and turns
// clicks into messages. No dependencies; KaTeX, highlight.js and Mermaid are
// loaded on demand when a document actually uses them.

(() => {
  'use strict';

  const post = (message) => {
    try { window.webkit.messageHandlers.galley.postMessage(message); } catch (_) { /* not in the app */ }
  };
  window.addEventListener('error', (e) => post({ type: 'log', message: `${e.message} (${e.filename}:${e.lineno}) ${e.error && e.error.stack || ''}` }));
  window.addEventListener('unhandledrejection', (e) => post({ type: 'log', message: String(e.reason) }));

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const esc = (text) => String(text ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const TOP_LINE = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--top')) + 24 || 88;

  let doc = null;          // the payload currently shown
  let generation = 0;      // bumps on every render; stale async work checks it
  let units = [];          // visible [data-b] elements, document order
  let headings = [];       // section headings, document order
  let mermaidSeq = 0;
  let lastReport = '';
  let lastReportTime = 0;
  let findState = { query: '', marks: [], index: -1 };
  let highlights = [];     // [{id, text, prefix, suffix}] for the document

  // — Lazy libraries ———————————————————————————————————————————————

  const loaded = new Map();
  function load(name) {
    if (loaded.has(name)) return loaded.get(name);
    const promise = new Promise((resolve, reject) => {
      const isCSS = name.endsWith('.css');
      const el = document.createElement(isCSS ? 'link' : 'script');
      el.crossOrigin = 'anonymous';
      if (isCSS) { el.rel = 'stylesheet'; el.href = `galley://app/${name}`; } else { el.src = `galley://app/${name}`; }
      el.onload = resolve;
      el.onerror = () => reject(new Error(`could not load ${name}`));
      document.head.appendChild(el);
    });
    loaded.set(name, promise);
    return promise;
  }

  // — Rendering ————————————————————————————————————————————————————

  function headerHTML(d) {
    const h = d.header || {};
    const parts = (h.meta || []).map((m) => `<span>${esc(m)}</span>`);
    if (h.badge) parts.push(`<span class="badge${h.badgeKind === 'new' ? ' new' : ''}">${esc(h.badge)}</span>`);
    const meta = parts.length ? `<div class="doc-meta">${parts.join('<span class="sep">·</span>')}</div>` : '';
    const title = h.title ? `<h1 class="derived">${esc(h.title)}</h1>` : '';
    return `<header class="doc-header">${meta}${title}</header>`;
  }

  /// The end of the document: room to breathe, and a quiet end mark when
  /// nothing follows. What comes next is shown only while pulling for it.
  function footerHTML(d) {
    if (!d.next && d.endLabel) {
      return `<footer class="doc-end end"><span class="title">${esc(d.endLabel)}</span></footer>`;
    }
    return '<footer class="doc-end"></footer>';
  }

  /// The pull cues — "Previous" above the page, "Next" below it. Fixed to
  /// the window, outside #page, so the page can stretch away from them and
  /// reveal one only while the reader pulls past an edge.
  function cueHTML(target, atStart) {
    if (!target) return '';
    const arrow = atStart ? 'M13 17.5V9.3M9.6 12.7 13 9.3l3.4 3.4' : 'M13 8.5v8.2M9.6 13.4 13 16.8l3.4-3.4';
    const why = target.why ? `<span class="why">${esc(target.why)}</span>` : '';
    return `<svg class="ring" viewBox="0 0 26 26"><circle class="track" cx="13" cy="13" r="11"/>` +
      `<circle class="fill" cx="13" cy="13" r="11" stroke-dasharray="69.12" stroke-dashoffset="69.12"/>` +
      `<path class="arrow" d="${arrow}"/></svg>` +
      `<span class="label">${esc(target.label || (atStart ? 'Previous' : 'Next'))}</span>` +
      `<span class="title">${esc(target.title)}</span>${why}`;
  }

  function renderCues(d) {
    for (const [id, target, atStart] of [['prev-pull', d.previous, true], ['next-pull', d.next, false]]) {
      let cue = document.getElementById(id);
      if (!cue) {
        cue = document.createElement('div');
        cue.id = id;
        cue.className = 'pull-cue';
        cue.setAttribute('aria-hidden', 'true');
        document.body.appendChild(cue);
      }
      cue.classList.remove('ready');
      cue.style.opacity = '';
      cue.innerHTML = cueHTML(target, atStart);
    }
  }

  function render(d) {
    generation += 1;
    doc = d;
    const page = $('#page');
    page.innerHTML = headerHTML(d) + `<div id="content">${d.html}</div>` + footerHTML(d) + '<div id="gutter"></div>';
    renderCues(d);
    page.style.translate = '';
    document.documentElement.classList.remove('pulling');
    if (d.header && d.header.title) {
      // A derived title would repeat a leading H1 in the document itself.
      const first = $('#content > .sec:first-child > h1:first-child, #content > h1:first-child');
      if (first) $('.doc-header h1.derived')?.remove();
    }
    resolveRawImages(d.base);
    applyChanges(d.changes || {});
    decorateSections(new Set(d.folded || []));
    decorateCode();
    findState = { query: '', marks: [], index: -1 };
    highlights = d.highlights || [];
    applyHighlights();
    index();
    layoutGutter();
    enhance(generation);
  }

  /// Images written as raw HTML (`<img src="diagram.png">`) resolve against
  /// the document's folder, like markdown images do in Swift.
  function resolveRawImages(base) {
    if (!base) return;
    for (const img of $$('#content img[src]')) {
      const src = img.getAttribute('src');
      if (/^[a-z][a-z0-9+.-]*:/i.test(src)) continue;
      try { img.src = new URL(src, base).href; } catch (_) { /* leave it */ }
    }
  }

  // — Changes ——————————————————————————————————————————————————————

  function applyChanges(changes) {
    for (const [key, change] of Object.entries(changes)) {
      const el = $(`#content [data-b="${key}"]`);
      if (!el) continue;
      el.classList.add('chg');
      if (change.kind === 'added' || el.tagName === 'PRE' || el.matches('.math, figure, dl')) {
        el.classList.add(change.kind === 'added' ? 'chg-added' : 'chg-modified');
        if (change.kind !== 'added' && el.tagName !== 'PRE') el.classList.add('chg-added');
        continue;
      }
      el.classList.add('chg-modified');
      markInsertions(el, change.old || '');
    }
    // Folded sections that hide a change say so on their heading.
    for (const sec of $$('#content .sec')) {
      if ($('.chg', sec)) sec.classList.add('has-change');
    }
  }

  const TOKEN = /\s+|[\p{L}\p{N}_'’]+|[^\s\p{L}\p{N}_]/gu;

  /// Wraps the words in `el` that are not in the old version in <ins>.
  function markInsertions(el, oldHTML) {
    const scratch = document.createElement('div');
    scratch.innerHTML = oldHTML;
    const a = scratch.textContent.match(TOKEN) || [];
    const b = el.textContent.match(TOKEN) || [];
    if (!b.length) return;
    if (a.length * b.length > 400000) { el.classList.add('chg-added'); return; }

    // Longest common subsequence over tokens.
    const n = a.length, m = b.length;
    const table = new Uint16Array((n + 1) * (m + 1));
    for (let i = n - 1; i >= 0; i--) {
      for (let j = m - 1; j >= 0; j--) {
        table[i * (m + 1) + j] = a[i] === b[j]
          ? table[(i + 1) * (m + 1) + j + 1] + 1
          : Math.max(table[(i + 1) * (m + 1) + j], table[i * (m + 1) + j + 1]);
      }
    }
    const inserted = new Array(m).fill(false);
    let i = 0, j = 0;
    while (j < m) {
      if (i < n && a[i] === b[j]) { i++; j++; }
      else if (i < n && table[(i + 1) * (m + 1) + j] >= table[i * (m + 1) + j + 1]) { i++; }
      else { inserted[j] = true; j++; }
    }

    // Whitespace counts as inserted only between inserted words.
    for (let k = 0; k < m; k++) {
      if (/^\s+$/.test(b[k])) inserted[k] = k > 0 && k < m - 1 && inserted[k - 1] && inserted[k + 1];
    }
    const words = b.filter((t) => !/^\s+$/.test(t)).length;
    const insertedWords = b.filter((t, k) => inserted[k] && !/^\s+$/.test(t)).length;
    if (!insertedWords) return;
    if (insertedWords / Math.max(words, 1) > 0.7) { el.classList.add('chg-added'); return; }

    const ranges = [];
    let offset = 0;
    for (let k = 0; k < m; k++) {
      const end = offset + b[k].length;
      if (inserted[k]) {
        const last = ranges[ranges.length - 1];
        if (last && last[1] === offset) last[1] = end; else ranges.push([offset, end]);
      }
      offset = end;
    }
    wrapRanges(el, ranges, 'ins', 'g-ins');
  }

  /// Wraps character ranges of `root`'s text in new elements, across text
  /// nodes and inline formatting. Returns the created elements.
  function wrapRanges(root, ranges, tag, className, skip) {
    const created = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, skip ? {
      acceptNode: (node) => (skip(node) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    } : null);
    const nodes = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode()) nodes.push(node);
    let offset = 0, r = 0;
    for (const node of nodes) {
      const start = offset, end = offset + node.data.length;
      offset = end;
      const pieces = [];
      while (r < ranges.length && ranges[r][0] < end) {
        const s = Math.max(ranges[r][0], start), e = Math.min(ranges[r][1], end);
        if (e > s) pieces.push([s - start, e - start, r]);
        if (ranges[r][1] <= end) r++; else break;
      }
      for (let k = pieces.length - 1; k >= 0; k--) {
        const [s, e, which] = pieces[k];
        const target = node.splitText(s);
        target.splitText(e - s);
        const wrapper = document.createElement(tag);
        wrapper.className = className;
        wrapper.dataset.range = which;
        target.parentNode.replaceChild(wrapper, target);
        wrapper.appendChild(target);
        created.unshift(wrapper);
      }
    }
    return created;
  }

  // — Gutter: change bars beside changed blocks ——————————————————————

  function layoutGutter() {
    const gutter = $('#gutter');
    if (!gutter) return;
    const pageTop = $('#page').getBoundingClientRect().top;
    const spans = [];
    for (const el of $$('#content .chg')) {
      if (!el.offsetParent) continue; // folded away
      if (el.parentElement.closest('.chg')) continue; // the outer block already has a bar
      const rect = el.getBoundingClientRect();
      if (!rect.height) continue;
      const top = rect.top - pageTop, bottom = top + rect.height;
      const last = spans[spans.length - 1];
      if (last && top - last[1] < 14) last[1] = Math.max(last[1], bottom);
      else spans.push([top, bottom]);
    }
    gutter.innerHTML = spans.map(([t, b]) => `<div class="bar" style="top:${t - 2}px;height:${b - t + 4}px"></div>`).join('');
  }

  // — Sections ——————————————————————————————————————————————————————

  function decorateSections(folded) {
    for (const sec of $$('#content .sec')) {
      const heading = sec.firstElementChild;
      if (!heading || !/^H[1-6]$/.test(heading.tagName)) continue;
      const button = document.createElement('button');
      button.className = 'fold';
      button.type = 'button';
      button.setAttribute('aria-label', 'Fold section');
      heading.prepend(button);
      if (folded.has(sec.dataset.sec)) sec.classList.add('folded');
    }
  }

  function setFolded(sec, folded, notify = true) {
    if (!sec || sec.classList.contains('folded') === folded) return;
    // Keep the heading where it is on screen while the content below changes.
    const heading = sec.firstElementChild;
    const before = heading.getBoundingClientRect().top;
    sec.classList.toggle('folded', folded);
    const after = heading.getBoundingClientRect().top;
    if (after !== before) window.scrollBy(0, after - before);
    if (notify) post({ type: 'fold', id: sec.dataset.sec, folded });
    index();
    layoutGutter();
    report(true);
  }

  // — Code ————————————————————————————————————————————————————————

  function decorateCode() {
    for (const pre of $$('#content pre')) {
      if (pre.classList.contains('mermaid-source') || pre.classList.contains('front-matter')) continue;
      const button = document.createElement('button');
      button.className = 'copy';
      button.type = 'button';
      button.textContent = 'Copy';
      pre.appendChild(button);
    }
  }

  // — Enhancements: math, code colour, diagrams —————————————————————

  async function enhance(gen) {
    const content = $('#content');
    try {
      if ($('.math', content)) {
        await Promise.all([load('katex.min.css'), load('katex.min.js')]);
        if (gen !== generation) return;
        renderMath(content);
      }
      const code = $$('pre > code[class*="language-"]', content);
      if (code.length) {
        await load('highlight.min.js');
        if (gen !== generation) return;
        window.hljs.configure({ ignoreUnescapedHTML: true });
        for (const el of code) {
          const language = (el.className.match(/language-([\w+#-]+)/) || [])[1];
          if (language && window.hljs.getLanguage(language)) window.hljs.highlightElement(el);
        }
      }
      if ($('figure.mermaid', content)) {
        await load('mermaid.min.js');
        if (gen !== generation) return;
        await renderMermaid(content, gen);
      }
    } catch (error) {
      post({ type: 'log', message: String(error) });
    }
    if (gen !== generation) return;
    // Code colouring and math replace their elements' contents: re-anchor.
    applyHighlights();
    index();
    layoutGutter();
    if (doc && doc.pendingScroll) { restore(doc.pendingScroll); doc.pendingScroll = null; }
  }

  function renderMath(root) {
    for (const el of $$('.math:not(.rendered)', root)) {
      const tex = el.dataset.tex ?? el.textContent;
      el.dataset.tex = tex;
      try {
        window.katex.render(tex, el, { displayMode: el.classList.contains('display'), throwOnError: false, output: 'htmlAndMathml' });
        el.classList.add('rendered');
      } catch (_) { /* leave the TeX visible */ }
    }
  }

  function mermaidTheme() {
    const style = getComputedStyle(document.documentElement);
    const v = (name) => style.getPropertyValue(name).trim();
    const dark = document.documentElement.classList.contains('dark');
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: 'base',
      fontFamily: v('--font-ui'),
      themeVariables: {
        darkMode: dark,
        background: v('--paper'),
        fontFamily: v('--font-ui'),
        fontSize: '14px',
        primaryColor: v('--code-bg'),
        primaryTextColor: v('--ink'),
        primaryBorderColor: v('--ink-3'),
        secondaryColor: v('--paper'),
        tertiaryColor: v('--code-bg'),
        lineColor: v('--ink-2'),
        textColor: v('--ink'),
        mainBkg: v('--code-bg'),
        nodeBorder: v('--ink-3'),
        clusterBkg: v('--paper'),
        clusterBorder: v('--rule'),
        edgeLabelBackground: v('--paper'),
        noteBkgColor: v('--code-bg'),
        noteTextColor: v('--ink'),
        noteBorderColor: v('--rule'),
        actorBkg: v('--code-bg'),
        actorBorder: v('--ink-3'),
        actorTextColor: v('--ink'),
        signalColor: v('--ink-2'),
        signalTextColor: v('--ink'),
      },
    });
  }

  async function renderMermaid(root, gen) {
    mermaidTheme();
    for (const figure of $$('figure.mermaid', root)) {
      const source = figure.dataset.source ?? $('.mermaid-source', figure)?.textContent ?? '';
      figure.dataset.source = source;
      try {
        const { svg } = await window.mermaid.render(`galley-mermaid-${++mermaidSeq}`, source);
        if (gen !== generation) return;
        figure.innerHTML = svg;
        figure.classList.add('rendered');
      } catch (error) {
        const message = String(error && error.message || error).split('\n')[0];
        figure.innerHTML = `<pre class="mermaid-error">${esc(source)}</pre><p class="mermaid-message">${esc(message)}</p>`;
      }
      // Mermaid leaves its scratch element behind on errors.
      document.getElementById(`dgalley-mermaid-${mermaidSeq}`)?.remove();
    }
  }

  // — Position ————————————————————————————————————————————————————

  function index() {
    units = $$('#content [data-b]').filter((el) => el.offsetParent !== null);
    headings = $$('#content .sec > :is(h1, h2, h3, h4, h5, h6)').filter((el) => el.offsetParent !== null);
  }

  /// The unit at the top of the viewport, and how far into it the reader is.
  function topAnchor() {
    const line = TOP_LINE();
    let lo = 0, hi = units.length - 1, found = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (units[mid].getBoundingClientRect().top <= line) { found = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    if (found < 0) return { unit: units.length ? Number(units[0].dataset.b) : -1, offset: 0 };
    const rect = units[found].getBoundingClientRect();
    const offset = rect.height ? Math.min(1, Math.max(0, (line - rect.top) / rect.height)) : 0;
    return { unit: Number(units[found].dataset.b), offset: Math.round(offset * 1000) / 1000 };
  }

  function currentHeading() {
    const line = TOP_LINE() + 8;
    let current = null;
    for (const h of headings) {
      if (h.getBoundingClientRect().top <= line) current = h.id; else break;
    }
    // At the very end, short last sections never reach the line: the last
    // heading on screen is the one being read.
    const max = document.documentElement.scrollHeight - window.innerHeight;
    if (window.scrollY >= max - 2) {
      const visible = headings.filter((h) => h.getBoundingClientRect().top < window.innerHeight * 0.75);
      if (visible.length) current = visible[visible.length - 1].id;
    }
    // At the top, the first heading counts once it is on screen.
    if (!current && headings[0] && headings[0].getBoundingClientRect().top < window.innerHeight * 0.6) current = headings[0].id;
    return current;
  }

  function report(force = false) {
    if (!doc) return;
    const max = document.documentElement.scrollHeight - window.innerHeight;
    const content = $('#content');
    const footerVisible = content ? content.getBoundingClientRect().bottom < window.innerHeight - 40 : true;
    const anchor = topAnchor();
    const state = {
      type: 'scroll',
      doc: doc.id,
      unit: anchor.unit,
      offset: anchor.offset,
      heading: currentHeading(),
      atTop: window.scrollY <= 1,
      atBottom: window.scrollY >= max - 2,
      reachedEnd: footerVisible,
      progress: max > 0 ? Math.min(1, window.scrollY / max) : 1,
    };
    const key = `${state.unit}|${state.heading}|${state.atTop}|${state.atBottom}|${state.reachedEnd}`;
    const now = Date.now();
    if (!force && key === lastReport && now - lastReportTime < 400) return;
    lastReport = key;
    lastReportTime = now;
    post(state);
  }

  let ticking = false;
  window.addEventListener('scroll', () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => { ticking = false; report(); });
  }, { passive: true });

  function restore(anchor) {
    if (!anchor) { window.scrollTo(0, 0); return; }
    if (anchor.unit === -2) { window.scrollTo(0, document.documentElement.scrollHeight); return; }
    let el = anchor.unit >= 0 ? $(`#content [data-b="${anchor.unit}"]`) : null;
    if (!el && anchor.heading) { scrollToHeading(anchor.heading, false); return; }
    if (!el) { window.scrollTo(0, 0); return; }
    if (!el.offsetParent) el = el.closest('.sec.folded')?.firstElementChild || el;
    const rect = el.getBoundingClientRect();
    window.scrollTo(0, Math.max(0, rect.top + window.scrollY - TOP_LINE() + (anchor.offset || 0) * rect.height));
  }

  function scrollToHeading(id, smooth = true) {
    const target = document.getElementById(id);
    if (!target) return;
    // Unfold any folded section that hides it.
    for (let sec = target.closest('.sec.folded'); sec; sec = sec.parentElement?.closest('.sec.folded')) {
      if (sec.firstElementChild !== target) setFolded(sec, false);
    }
    const top = target.getBoundingClientRect().top + window.scrollY - TOP_LINE() + 16;
    window.scrollTo({ top: Math.max(0, top), behavior: smooth ? 'smooth' : 'auto' });
  }

  // — Find ————————————————————————————————————————————————————————

  function clearFind() {
    for (const mark of findState.marks) {
      const parent = mark.parentNode;
      if (!parent) continue;
      while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
      parent.removeChild(mark);
      parent.normalize();
    }
    findState = { query: '', marks: [], index: -1 };
  }

  function find(query, direction, quiet = false) {
    const content = $('#content');
    if (!content) return { count: 0, index: -1 };
    if (query !== findState.query) {
      clearFind();
      findState.query = query;
      if (query) {
        // Same text the wrapper walks: no button labels, MathML or SVG.
        const text = readingText(content);
        const needle = query.toLocaleLowerCase();
        const haystack = text.toLocaleLowerCase();
        const ranges = [];
        for (let at = haystack.indexOf(needle); at >= 0 && ranges.length < 2000; at = haystack.indexOf(needle, at + needle.length)) {
          ranges.push([at, at + needle.length]);
        }
        const created = wrapRanges(content, ranges, 'mark', 'find', skipForText);
        // A match split across nodes becomes several marks; group them by range.
        const groups = new Map();
        for (const mark of created) {
          const key = mark.dataset.range;
          if (!groups.has(key)) groups.set(key, []);
          groups.get(key).push(mark);
        }
        findState.marks = created;
        findState.groups = Array.from(groups.values());
        findState.index = -1;
      }
    }
    const groups = findState.groups || [];
    if (!groups.length) return { count: 0, index: -1 };
    if (quiet) return { count: groups.length, index: -1 };
    for (const mark of findState.marks) mark.classList.remove('current');
    if (findState.index < 0) {
      // Start from the first match below the current reading position.
      const line = TOP_LINE();
      findState.index = groups.findIndex((g) => g[0].getBoundingClientRect().top >= line - 4);
      if (findState.index < 0) findState.index = 0;
      if (direction < 0) findState.index = (findState.index - 1 + groups.length) % groups.length;
    } else {
      findState.index = (findState.index + direction + groups.length) % groups.length;
    }
    const group = groups[findState.index];
    for (const mark of group) mark.classList.add('current');
    const sec = group[0].closest('.sec.folded');
    if (sec) setFolded(sec, false);
    group[0].scrollIntoView({ block: 'center', behavior: 'smooth' });
    return { count: groups.length, index: findState.index };
  }

  // — Highlights ——————————————————————————————————————————————————
  //
  // A highlight is its text plus a little context either side, measured in
  // the content's reading text (no button labels, no MathML, no SVG). It is
  // re-found by text, never by position, so it survives the file being
  // rewritten around it; when the text is gone it becomes an orphan.

  const CONTEXT = 48;
  const skipForText = (node) => node.parentElement && node.parentElement.closest('button, .katex-mathml, svg, .copy, .hl-note, .html-comment');

  function readingNodes(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => (skipForText(node) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT),
    });
    const nodes = [];
    for (let node = walker.nextNode(); node; node = walker.nextNode()) nodes.push(node);
    return nodes;
  }

  function readingText(root) {
    return readingNodes(root).map((n) => n.data).join('');
  }

  /// A DOM boundary point as an offset into the reading text.
  function readingOffset(root, container, offset) {
    const nodes = readingNodes(root);
    let total = 0;
    if (container.nodeType === Node.TEXT_NODE && nodes.includes(container)) {
      for (const node of nodes) {
        if (node === container) return total + offset;
        total += node.data.length;
      }
    }
    const boundary = document.createRange();
    boundary.setStart(container, offset);
    for (const node of nodes) {
      if (boundary.comparePoint(node, 0) >= 0) break;
      total += node.data.length;
    }
    return total;
  }

  const BLOCK = 'p, li, h1, h2, h3, h4, h5, h6, td, th, pre, blockquote, dt, dd, figcaption, summary, caption';

  /// Reading-text offsets where one block ends and the next begins.
  function blockBreaks(root) {
    const breaks = new Set();
    let total = 0, previous = null;
    for (const node of readingNodes(root)) {
      const block = node.parentElement.closest(BLOCK);
      if (total > 0 && block !== previous) breaks.add(total);
      previous = block;
      total += node.data.length;
    }
    return breaks;
  }

  // WebKit drops the page's selection when the web view stops being first
  // responder, as it does when the palette's field takes the keys. The
  // palette keeps it as it opens and puts it back as it closes, so its
  // Highlight and Add Note have something to work on.
  let keptRange = null;

  function keepSelection() {
    const selection = window.getSelection();
    keptRange = selection.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0).cloneRange() : null;
    return keptRange !== null;
  }

  function restoreSelection() {
    const range = keptRange;
    keptRange = null;
    const selection = window.getSelection();
    // Not over a newer selection, nor into a page that was drawn again.
    if (!range || !range.startContainer.isConnected || !range.endContainer.isConnected) return false;
    if (selection.rangeCount && !selection.isCollapsed) return false;
    selection.removeAllRanges();
    selection.addRange(range);
    return true;
  }

  function selectionAnchor() {
    const content = $('#content');
    const selection = window.getSelection();
    if (!content || !selection.rangeCount || selection.isCollapsed) return null;
    const range = selection.getRangeAt(0);
    if (!content.contains(range.commonAncestorContainer)) return null;
    // Text chosen inside a note is the reader's own words, not the document's.
    const ancestor = range.commonAncestorContainer;
    if ((ancestor.nodeType === Node.ELEMENT_NODE ? ancestor : ancestor.parentElement).closest('.hl-note')) return null;
    const full = readingText(content);
    const start = readingOffset(content, range.startContainer, range.startOffset);
    const end = readingOffset(content, range.endContainer, range.endOffset);
    // A selection touching existing highlights grows to cover them and
    // replaces them, so highlights never overlap.
    let from = start, to = end;
    const replaces = [];
    for (const mark of $$('#content mark.hl')) {
      if (!range.intersectsNode(mark)) continue;
      const id = mark.dataset.id;
      if (!replaces.includes(id)) replaces.push(id);
      const markStart = readingOffset(content, mark, 0);
      from = Math.min(from, markStart);
      to = Math.max(to, markStart + mark.textContent.length);
    }
    for (const id of replaces) {
      const marks = $$(`#content mark.hl[data-id="${CSS.escape(id)}"]`);
      const first = readingOffset(content, marks[0], 0);
      const last = marks[marks.length - 1];
      from = Math.min(from, first);
      to = Math.max(to, readingOffset(content, last, 0) + last.textContent.length);
    }
    // A drag that stops a letter short, or starts one in, still means the
    // word: highlights cover whole words, as in Books. Never across blocks:
    // the reading text runs one block into the next with nothing between,
    // so a drag that ends at the very start of the next heading would
    // otherwise take its first word along.
    const breaks = blockBreaks(content);
    const word = /[\p{L}\p{N}'’-]/u;
    while (from > 0 && !breaks.has(from) && word.test(full[from - 1]) && word.test(full[from])) from--;
    while (to < full.length && !breaks.has(to) && word.test(full[to]) && word.test(full[to - 1])) to++;
    while (from < to && /\s/.test(full[from])) from++;
    while (to > from && /\s/.test(full[to - 1])) to--;
    const text = full.slice(from, to);
    if (!text.trim()) return null;
    return { text, prefix: full.slice(Math.max(0, from - CONTEXT), from), suffix: full.slice(to, to + CONTEXT), replaces };
  }

  /// Where `h` sits in `full` now: the occurrence whose surroundings best
  /// match the saved context.
  function locate(h, full) {
    let best = -1, bestScore = -1;
    for (let at = full.indexOf(h.text); at >= 0; at = full.indexOf(h.text, at + 1)) {
      const before = full.slice(Math.max(0, at - CONTEXT), at);
      const after = full.slice(at + h.text.length, at + h.text.length + CONTEXT);
      let score = 0;
      while (score < before.length && score < h.prefix.length &&
             before[before.length - 1 - score] === h.prefix[h.prefix.length - 1 - score]) score++;
      let tail = 0;
      while (tail < after.length && tail < h.suffix.length && after[tail] === h.suffix[tail]) tail++;
      if (score + tail > bestScore) { bestScore = score + tail; best = at; }
    }
    // A long passage is distinctive on its own. A short one ("day.") must
    // also agree with some of its old surroundings, or it would latch onto
    // the next word that happens to contain it.
    const distinctive = h.text.trim().length >= 24;
    const needed = Math.min(8, h.prefix.length + h.suffix.length);
    if (best >= 0 && !distinctive && bestScore < needed) return -1;
    return best;
  }

  function clearHighlights() {
    for (const note of $$('#content .hl-note')) note.remove();
    for (const mark of $$('#content mark.hl')) {
      const parent = mark.parentNode;
      while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
      parent.removeChild(mark);
      parent.normalize();
    }
  }

  function applyHighlights() {
    const content = $('#content');
    if (!content) return;
    clearHighlights();
    if (!highlights.length) { post({ type: 'orphans', ids: [] }); return; }
    const full = readingText(content);
    const found = [];
    const orphans = [];
    for (const h of highlights) {
      const at = locate(h, full);
      if (at < 0) orphans.push(h.id); else found.push({ id: h.id, range: [at, at + h.text.length] });
    }
    found.sort((a, b) => a.range[0] - b.range[0]);
    // Overlaps (older data, or two highlights re-anchoring onto one spot)
    // would break the wrapper: keep the earlier one's extent.
    const placed = [];
    for (const f of found) {
      const last = placed[placed.length - 1];
      if (last && f.range[0] < last.range[1]) {
        if (f.range[1] > last.range[1]) placed.push({ id: f.id, range: [last.range[1], f.range[1]] });
        continue;
      }
      placed.push(f);
    }
    found.length = 0;
    found.push(...placed);
    const marks = wrapRanges(content, found.map((f) => f.range), 'mark', 'hl', skipForText);
    for (const mark of marks) mark.dataset.id = found[Number(mark.dataset.range)].id;
    renderNotes(found.map((f) => f.id));
    post({ type: 'orphans', ids: orphans });
  }

  // — Notes ————————————————————————————————————————————————————————
  //
  // A note is the reader's word on a highlight: a small card under the
  // block the highlight ends in (inside it, for a list item or a cell), so
  // it reads in place at any width. Cards are not document text.

  let pendingNote = null;

  function noteBlock(mark) {
    // The front matter is a grid of names and values: the card goes under
    // the whole of it, not into the grid as one more cell.
    const front = mark.closest('dl.front-matter');
    if (front) return { el: front, inside: false };
    const inner = mark.closest('li, td, th');
    if (inner) return { el: inner, inside: true };
    const block = mark.closest('p, h1, h2, h3, h4, h5, h6, blockquote, pre, dd, dt, figure, .callout, table');
    return block ? { el: block, inside: false } : null;
  }

  function renderNotes(placedIds) {
    const byId = new Map(highlights.map((h) => [h.id, h]));
    // Cards stack under a block in the order their highlights appear.
    const lastOf = new Map();
    for (const id of placedIds) {
      const h = byId.get(id);
      if (!h || (!h.note && pendingNote !== id)) continue;
      const marks = $$(`#content mark.hl[data-id="${CSS.escape(id)}"]`);
      const place = marks.length ? noteBlock(marks[marks.length - 1]) : null;
      if (!place) continue;
      const card = noteCard(h);
      const after = lastOf.get(place.el);
      if (after) after.after(card);
      else if (place.inside) place.el.appendChild(card);
      else place.el.after(card);
      lastOf.set(place.el, card);
    }
    // Wait for the app to have the highlight: a render in between keeps it pending.
    const card = pendingNote && $(`#content .hl-note[data-id="${CSS.escape(pendingNote)}"]`);
    if (card) { pendingNote = null; editCard(card); }
  }

  function noteCard(h) {
    const card = document.createElement('aside');
    card.className = 'hl-note';
    card.dataset.id = h.id;
    card.setAttribute('aria-label', 'Note');
    showCardText(card, h.note || '');
    return card;
  }

  function showCardText(card, text) {
    card.classList.remove('editing');
    card.innerHTML = '';
    const body = document.createElement('div');
    body.className = 'hl-note-text';
    body.textContent = text;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'hl-note-remove';
    remove.title = 'Delete note (the highlight stays)';
    remove.textContent = '×';
    remove.addEventListener('mousedown', (e) => e.preventDefault());
    remove.addEventListener('click', (e) => { e.stopPropagation(); post({ type: 'note', id: card.dataset.id, text: '' }); });
    card.append(body, remove);
  }

  function editCard(card) {
    if (card.classList.contains('editing')) { card.querySelector('textarea')?.focus(); return; }
    const h = highlights.find((x) => x.id === card.dataset.id);
    const original = h?.note || '';
    card.classList.add('editing');
    card.innerHTML = '';
    const field = document.createElement('textarea');
    field.value = original;
    field.placeholder = 'What should change here?';
    field.rows = 1;
    const hint = document.createElement('div');
    hint.className = 'hl-note-hint';
    hint.textContent = '⌘↩ to save · Esc to cancel';
    card.append(field, hint);
    const fit = () => { field.style.height = 'auto'; field.style.height = `${field.scrollHeight}px`; };
    let done = false;
    const finish = (save) => {
      if (done) return;
      done = true;
      const text = field.value.trim();
      if (save && text !== original.trim()) {
        post({ type: 'note', id: card.dataset.id, text });
      } else if (!original) {
        card.remove(); // a new note left empty: nothing to keep
      } else {
        showCardText(card, original);
      }
    };
    field.addEventListener('input', fit);
    field.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Escape') { e.preventDefault(); finish(false); }
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); finish(true); }
    });
    field.addEventListener('blur', () => finish(true));
    requestAnimationFrame(() => { fit(); field.focus(); field.setSelectionRange(field.value.length, field.value.length); });
  }

  function editNote(id) {
    const card = $(`#content .hl-note[data-id="${CSS.escape(id)}"]`);
    if (card) { card.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); editCard(card); return; }
    // No card yet: render one in edit mode.
    pendingNote = id;
    applyHighlights();
    $(`#content .hl-note[data-id="${CSS.escape(id)}"]`)?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  /// Highlights the selection and opens a note on it.
  function noteSelection() {
    const anchor = selectionAnchor();
    if (!anchor) return false;
    const id = crypto.randomUUID();
    pendingNote = id;
    post({ type: 'highlight', ...anchor, id });
    window.getSelection().removeAllRanges();
    return true;
  }

  function scrollToHighlight(id) {
    const mark = $(`#content mark.hl[data-id="${CSS.escape(id)}"]`);
    if (!mark) return;
    const sec = mark.closest('.sec.folded');
    if (sec) setFolded(sec, false);
    mark.scrollIntoView({ block: 'center', behavior: 'smooth' });
    const group = $$(`#content mark.hl[data-id="${CSS.escape(id)}"]`);
    for (const m of group) { m.classList.remove('flash-hl'); void m.offsetWidth; m.classList.add('flash-hl'); }
  }

  // The pill over a selection (highlight it, or note it) or over a
  // highlight (note it, or remove it).
  let pill = null;
  function hidePill() { pill?.remove(); pill = null; }
  function showPill(rect, actions) {
    hidePill();
    pill = document.createElement('div');
    pill.className = 'pill';
    pill.addEventListener('mousedown', (e) => e.preventDefault());
    for (const action of actions) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = action.label;
      button.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); hidePill(); action.run(); });
      pill.appendChild(button);
    }
    document.body.appendChild(pill);
    const width = pill.offsetWidth;
    const top = rect.top + window.scrollY - pill.offsetHeight - 8;
    const left = Math.min(window.innerWidth - width - 8, Math.max(8, rect.left + rect.width / 2 - width / 2));
    pill.style.top = `${Math.max(window.scrollY + 8, top)}px`;
    pill.style.left = `${left}px`;
  }

  document.addEventListener('mouseup', (event) => {
    if (event.target.closest('.pill')) return;
    setTimeout(() => {
      if (event.target.closest('.hl-note')) {
        const card = event.target.closest('.hl-note');
        if (window.getSelection().isCollapsed && !event.target.closest('button')) editCard(card);
        return;
      }
      const anchor = selectionAnchor();
      if (anchor) {
        const rect = window.getSelection().getRangeAt(0).getBoundingClientRect();
        showPill(rect, [
          { label: 'Highlight', run: () => { post({ type: 'highlight', ...anchor }); window.getSelection().removeAllRanges(); } },
          { label: 'Add Note', run: () => noteSelection() },
        ]);
        return;
      }
      const mark = event.target.closest('mark.hl');
      if (mark && window.getSelection().isCollapsed) {
        const id = mark.dataset.id;
        const hasNote = highlights.some((h) => h.id === id && h.note);
        showPill(mark.getBoundingClientRect(), [
          { label: hasNote ? 'Edit Note' : 'Add Note', run: () => editNote(id) },
          { label: 'Remove', run: () => post({ type: 'unhighlight', id }) },
        ]);
        return;
      }
      hidePill();
    }, 0);
  });
  window.addEventListener('scroll', () => { if (pill && !window.getSelection().isCollapsed) return; hidePill(); }, { passive: true });
  document.addEventListener('keydown', (event) => { if (event.key === 'Escape') hidePill(); });

  // — Input ———————————————————————————————————————————————————————

  document.addEventListener('click', (event) => {
    const fold = event.target.closest('button.fold');
    if (fold) {
      event.preventDefault();
      const sec = fold.closest('.sec');
      setFolded(sec, !sec.classList.contains('folded'));
      return;
    }
    const copy = event.target.closest('pre > button.copy');
    if (copy) {
      event.preventDefault();
      const code = copy.parentElement.querySelector('code') || copy.parentElement;
      post({ type: 'copy', text: code.textContent });
      copy.textContent = 'Copied';
      copy.classList.add('done');
      setTimeout(() => { copy.textContent = 'Copy'; copy.classList.remove('done'); }, 1400);
      return;
    }
    const link = event.target.closest('a[href]');
    if (link) {
      event.preventDefault();
      const href = link.getAttribute('href');
      if (href.startsWith('#')) {
        const id = decodeURIComponent(href.slice(1));
        const target = document.getElementById(id);
        if (target) {
          target.closest('.sec.folded') && setFolded(target.closest('.sec.folded'), false);
          const top = target.getBoundingClientRect().top + window.scrollY - TOP_LINE() + 16;
          window.scrollTo({ top, behavior: 'smooth' });
          target.classList.remove('flash'); void target.offsetWidth; target.classList.add('flash');
        }
      } else {
        post({ type: 'link', href });
      }
      return;
    }
  });

  document.addEventListener('mouseover', (event) => {
    const link = event.target.closest('a[href]');
    if (link && !link.title) {
      const href = link.getAttribute('href');
      if (!href.startsWith('#')) link.title = href.startsWith('wiki:') ? href.slice(5) : href;
    }
  });

  new ResizeObserver(() => { layoutGutter(); }).observe(document.documentElement);
  document.addEventListener('toggle', () => { index(); layoutGutter(); }, true);

  // — API for Swift ————————————————————————————————————————————————

  window.Reader = {
    configure(config) {
      const root = document.documentElement;
      for (const [name, value] of Object.entries(config.vars || {})) root.style.setProperty(name, value);
      root.style.setProperty('--font-body', config.font);
      root.style.setProperty('--size', `${config.size}px`);
      root.style.setProperty('--leading', String(config.leading));
      root.style.setProperty('--measure', `${config.measure}em`);
      root.style.setProperty('--top', `${config.top}px`);
      root.classList.toggle('dark', !!config.dark);
      root.classList.toggle('hide-changes', !config.showChanges);
      root.classList.toggle('show-comments', !!config.showComments);
      root.style.colorScheme = config.dark ? 'dark' : 'light';
      if (config.lang) root.lang = config.lang;
      const anchor = doc ? topAnchor() : null;
      requestAnimationFrame(() => {
        if (anchor && anchor.unit >= 0) restore(anchor);
        index();
        layoutGutter();
        if (window.mermaid && $('figure.mermaid.rendered')) {
          for (const figure of $$('figure.mermaid')) figure.classList.remove('rendered');
          renderMermaid($('#content'), generation);
        }
      });
    },

    /// A new document. `transition` is 'none', 'up' (next) or 'down' (previous).
    show(d) {
      const page = $('#page');
      document.documentElement.classList.remove('pulling', 'pull-armed');
      const go = () => {
        render(d);
        restore(d.scroll);
        if (d.scroll) d.pendingScroll = d.scroll; // re-apply once math and code settle
        report(true);
      };
      if (!d.transition || d.transition === 'none' || !doc || matchMedia('(prefers-reduced-motion: reduce)').matches) {
        page.className = '';
        go();
        return;
      }
      const up = d.transition === 'up';
      page.className = up ? 'leaving-up' : 'leaving-down';
      setTimeout(() => {
        page.className = up ? 'entering-up' : 'entering-down';
        go();
        requestAnimationFrame(() => requestAnimationFrame(() => { page.className = 'settle'; }));
        setTimeout(() => { page.className = ''; }, 460);
      }, 150);
    },

    /// The same document, changed on disk: keep the reader's place.
    update(d) {
      const anchor = topAnchor();
      const offsetBefore = (() => {
        const el = $(`#content [data-b="${anchor.unit}"]`);
        return el ? el.getBoundingClientRect().top : null;
      })();
      const findQuery = findState.query;
      render(d);
      const el = $(`#content [data-b="${anchor.unit}"]`);
      if (el && offsetBefore !== null) window.scrollBy(0, el.getBoundingClientRect().top - offsetBefore);
      if (findQuery) find(findQuery, 0, true);
      report(true);
    },

    scrollToHeading(id) { scrollToHeading(id, true); },
    /// A pull past an edge, in points of finger travel: the page stretches
    /// away from the edge with growing resistance, and the cue it reveals
    /// fills its ring toward `threshold`. 0 springs the page back.
    setPull(points, threshold, atStart) {
      const root = document.documentElement;
      const page = $('#page');
      const cue = document.getElementById(atStart ? 'prev-pull' : 'next-pull');
      const p = Math.max(0, points);
      const offset = p ? 130 * p / (p + 150) : 0;
      root.classList.toggle('pulling', p > 0);
      page.style.translate = p ? `0 ${(atStart ? offset : -offset).toFixed(1)}px` : '';
      if (!cue) return;
      const fill = $('.ring .fill', cue);
      if (fill) fill.setAttribute('stroke-dashoffset', String(69.12 * (1 - Math.min(1, p / threshold))));
      cue.style.opacity = p ? String(Math.min(1, Math.max(0, (offset - 8) / 28))) : '';
      cue.classList.toggle('ready', p >= threshold);
    },
    /// While panels slide, the page's length changes on every frame and the
    /// overlay scrollbar would keep popping up and moving: hide it.
    setPanelsMoving(moving) { document.documentElement.classList.toggle('panels-moving', moving); },
    /// While a pull may start, WebKit's own bounce stays out of the way.
    armPull(armed) { document.documentElement.classList.toggle('pull-armed', armed); },
    fold(id, folded) { setFolded($(`#content .sec[data-sec="${CSS.escape(id)}"]`), folded, false); },
    foldAll(folded) {
      const sections = $$('#content .sec');
      // Fold the first level that structures the document: below a lone
      // title heading, the level of its sections.
      const levels = [...new Set(sections.map((s) => Number(s.dataset.level)))].sort((a, b) => a - b);
      let level = levels[0];
      if (levels.length > 1 && sections.filter((s) => Number(s.dataset.level) === level).length === 1) level = levels[1];
      const targets = folded ? sections.filter((s) => Number(s.dataset.level) === level && $('.sec-body > *', s)) : sections;
      for (const sec of targets) sec.classList.toggle('folded', folded);
      index();
      layoutGutter();
      post({ type: 'folds', ids: $$('#content .sec.folded').map((s) => s.dataset.sec) });
      report(true);
    },
    jumpToChange(direction) {
      const line = TOP_LINE() + 4;
      const changes = $$('#content .chg').filter((el) => !el.parentElement.closest('.chg'));
      if (!changes.length) return false;
      let target;
      if (direction > 0) target = changes.find((el) => el.offsetParent && el.getBoundingClientRect().top > line + 6);
      else target = changes.filter((el) => el.offsetParent && el.getBoundingClientRect().top < line - 6).pop();
      if (!target) target = direction > 0 ? changes.find((el) => !el.offsetParent) : null;
      if (!target) return false;
      const sec = target.closest('.sec.folded');
      if (sec) setFolded(sec, false);
      const top = target.getBoundingClientRect().top + window.scrollY - TOP_LINE() - 8;
      window.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
      target.classList.remove('flash'); void target.offsetWidth; target.classList.add('flash');
      return true;
    },
    find(query, direction) { return find(query, direction); },
    setHighlights(list) { highlights = list || []; applyHighlights(); },
    scrollToHighlight(id) { scrollToHighlight(id); },
    editNote(id) { editNote(id); },
    noteSelection() { return noteSelection(); },
    /// For the menu command: the selection as a highlight anchor, or null.
    selectionAnchor() { const a = selectionAnchor(); hidePill(); return a; },
    endFind() { clearFind(); },
    selectionText() { return window.getSelection().toString(); },
    keepSelection() { return keepSelection(); },
    restoreSelection() { return restoreSelection(); },
    scrollPage(direction) { window.scrollBy({ top: direction * (window.innerHeight - 80), behavior: 'smooth' }); },
  };

  // Errors from scripts on a custom scheme reach window.onerror as an opaque
  // "Script error."; catching at the API boundary keeps the real message.
  for (const [name, fn] of Object.entries(window.Reader)) {
    window.Reader[name] = (...args) => {
      try { return fn(...args); } catch (error) {
        post({ type: 'log', message: `Reader.${name}: ${error && error.stack || error}` });
        throw error;
      }
    };
  }
  document.addEventListener('DOMContentLoaded', () => post({ type: 'ready' }));
})();
