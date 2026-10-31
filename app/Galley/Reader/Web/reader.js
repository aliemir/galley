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
  window.addEventListener('error', (e) => post({ type: 'log', message: `${e.message} (${e.filename}:${e.lineno})` }));
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

  // — Lazy libraries ———————————————————————————————————————————————

  const loaded = new Map();
  function load(name) {
    if (loaded.has(name)) return loaded.get(name);
    const promise = new Promise((resolve, reject) => {
      const isCSS = name.endsWith('.css');
      const el = document.createElement(isCSS ? 'link' : 'script');
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

  function footerHTML(d) {
    const ring = `<svg class="ring" viewBox="0 0 26 26" aria-hidden="true"><circle class="track" cx="13" cy="13" r="11"/>` +
      `<circle class="fill" cx="13" cy="13" r="11" stroke-dasharray="69.12" stroke-dashoffset="69.12"/>` +
      `<path class="arrow" d="M13 8.5v8.2M9.6 13.4 13 16.8l3.4-3.4"/></svg>`;
    if (!d.next) {
      return `<footer class="next end"><span class="title">${esc(d.endLabel || 'End of the stack')}</span></footer>`;
    }
    const why = d.next.why ? `<span class="why">${esc(d.next.why)}</span>` : '';
    return `<footer class="next">${ring}<span class="label">${esc(d.next.label || 'Next')}</span>` +
      `<span class="title">${esc(d.next.title)}</span>${why}</footer>`;
  }

  function render(d) {
    generation += 1;
    doc = d;
    const page = $('#page');
    page.innerHTML = headerHTML(d) + `<div id="content">${d.html}</div>` + footerHTML(d) + '<div id="gutter"></div>';
    if (d.header && d.header.title) {
      // A derived title would repeat a leading H1 in the document itself.
      const first = $('#content > .sec:first-child > h1:first-child, #content > h1:first-child');
      if (first) $('.doc-header h1.derived')?.remove();
    }
    applyChanges(d.changes || {});
    decorateSections(new Set(d.folded || []));
    decorateCode();
    findState = { query: '', marks: [], index: -1 };
    index();
    layoutGutter();
    enhance(generation);
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
    const footer = $('footer.next');
    const footerVisible = footer ? footer.getBoundingClientRect().top < window.innerHeight - 40 : true;
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
    if (anchor.heading) { scrollToHeading(anchor.heading, false); return; }
    let el = $(`#content [data-b="${anchor.unit}"]`);
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

  function find(query, direction) {
    const content = $('#content');
    if (!content) return { count: 0, index: -1 };
    if (query !== findState.query) {
      clearFind();
      findState.query = query;
      if (query) {
        const text = content.textContent;
        const needle = query.toLocaleLowerCase();
        const haystack = text.toLocaleLowerCase();
        const ranges = [];
        for (let at = haystack.indexOf(needle); at >= 0 && ranges.length < 2000; at = haystack.indexOf(needle, at + needle.length)) {
          ranges.push([at, at + needle.length]);
        }
        const skip = (node) => node.parentElement && node.parentElement.closest('.katex-mathml, button, svg');
        const created = wrapRanges(content, ranges, 'mark', 'find', skip);
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
    const next = event.target.closest('footer.next:not(.end)');
    if (next && window.getSelection().isCollapsed) post({ type: 'next' });
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
      if (findQuery) find(findQuery, 0);
      report(true);
    },

    scrollToHeading(id) { scrollToHeading(id, true); },
    setPull(progress) {
      const footer = $('footer.next:not(.end)');
      if (!footer) return;
      const fill = $('.ring .fill', footer);
      if (fill) fill.setAttribute('stroke-dashoffset', String(69.12 * (1 - Math.min(1, progress))));
      footer.classList.toggle('ready', progress >= 1);
    },
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
    endFind() { clearFind(); },
    selectionText() { return window.getSelection().toString(); },
    scrollPage(direction) { window.scrollBy({ top: direction * (window.innerHeight - 80), behavior: 'smooth' }); },
  };

  document.addEventListener('DOMContentLoaded', () => post({ type: 'ready' }));
})();
