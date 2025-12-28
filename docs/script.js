const $ = (q) => document.querySelector(q);

const state = {
  data: null,
  query: "",
  compact: false
};

function escapeHtml(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function normalize(s) {
  return String(s ?? "").toLowerCase().trim();
}

function parseYouTubeId(url) {
  try {
    const u = new URL(url);
    if (u.hostname.includes("youtu.be")) return u.pathname.replace("/", "");
    if (u.searchParams.get("v")) return u.searchParams.get("v");
    const parts = u.pathname.split("/").filter(Boolean);
    const embedIndex = parts.indexOf("embed");
    if (embedIndex !== -1 && parts[embedIndex + 1]) return parts[embedIndex + 1];
  } catch {}
  return null;
}

function matchesQuery(section, item, q) {
  if (!q) return true;
  const hay = [
    section?.name,
    section?.description,
    item?.title,
    item?.note,
    ...(item?.tags || [])
  ].map(normalize).join(" | ");
  return hay.includes(q);
}

function badgeLabel(type) {
  if (type === "image") return "Image";
  if (type === "video") return "Video";
  if (type === "youtube") return "YouTube";
  return "Item";
}

function makeThumb(item) {
  const type = item.type;
  const title = escapeHtml(item.title);

  if (type === "image") {
    return `
      <div class="thumb">
        <span class="badge">${badgeLabel(type)}</span>
        <img src="${escapeHtml(item.src)}" alt="${title}">
      </div>
    `;
  }

  if (type === "video") {
    return `
      <div class="thumb">
        <span class="badge">${badgeLabel(type)}</span>
        <div class="play">▶</div>
        <video preload="metadata" muted playsinline>
          <source src="${escapeHtml(item.src)}" type="video/mp4">
        </video>
      </div>
    `;
  }

  if (type === "youtube") {
    const id = parseYouTubeId(item.src);
    const thumb = id ? `https://i.ytimg.com/vi/${id}/hqdefault.jpg` : "";
    return `
      <div class="thumb">
        <span class="badge">${badgeLabel(type)}</span>
        <div class="play">▶</div>
        ${thumb ? `<img src="${thumb}" alt="${title}">` : `<div></div>`}
      </div>
    `;
  }

  return `
    <div class="thumb">
      <span class="badge">${badgeLabel(type)}</span>
    </div>
  `;
}

function render() {
  const status = $("#status");
  const root = $("#sections");

  if (!state.data) {
    status.textContent = "Loading…";
    root.innerHTML = "";
    return;
  }

  document.title = state.data.title || "Work";
  const q = normalize(state.query);

  const sections = Array.isArray(state.data.sections) ? state.data.sections : [];
  const rendered = [];

  let totalVisible = 0;

  for (const section of sections) {
    const items = Array.isArray(section.items) ? section.items : [];
    const visibleItems = items.filter((it) => matchesQuery(section, it, q));

    if (visibleItems.length === 0) continue;

    totalVisible += visibleItems.length;

    const cards = visibleItems.map((it, idx) => {
      const tags = (it.tags || []).slice(0, 6).map(t => `<span class="tag">${escapeHtml(t)}</span>`).join("");
      const note = it.note ? `<div class="cardNote">${escapeHtml(it.note)}</div>` : "";

      return `
        <div class="card" role="button" tabindex="0"
             data-section="${escapeHtml(section.name)}"
             data-index="${idx}"
             data-type="${escapeHtml(it.type)}"
             data-title="${escapeHtml(it.title)}"
             data-src="${escapeHtml(it.src)}"
             data-note="${escapeHtml(it.note || "")}"
             data-tags="${escapeHtml((it.tags || []).join(", "))}">
          ${makeThumb(it)}
          <div class="body">
            <div class="cardTitle">${escapeHtml(it.title)}</div>
            ${note}
            ${tags ? `<div class="tags">${tags}</div>` : ""}
          </div>
        </div>
      `;
    }).join("");

    rendered.push(`
      <section class="section">
        <div class="sectionHead">
          <div>
            <div class="sectionName">${escapeHtml(section.name)}</div>
            ${section.description ? `<div class="sectionDesc">${escapeHtml(section.description)}</div>` : ""}
          </div>
          <div class="sectionMeta">${visibleItems.length} item${visibleItems.length === 1 ? "" : "s"}</div>
        </div>
        <div class="grid">${cards}</div>
      </section>
    `);
  }

  if (!rendered.length) {
    status.textContent = q ? `No results for “${state.query}”.` : "No sections/items found. Edit data.json to add work.";
    root.innerHTML = "";
    return;
  }

  status.textContent = q ? `${totalVisible} result${totalVisible === 1 ? "" : "s"} for “${state.query}”.` : `${totalVisible} item${totalVisible === 1 ? "" : "s"} loaded.`;
  root.innerHTML = rendered.join("");
  wireCards();
}

function openModal(payload) {
  const modal = $("#modal");
  const body = $("#modalBody");
  const title = $("#modalTitle");
  const meta = $("#modalMeta");

  title.textContent = payload.title || "";

  let mediaHtml = "";
  if (payload.type === "image") {
    mediaHtml = `<img src="${escapeHtml(payload.src)}" alt="${escapeHtml(payload.title)}">`;
  } else if (payload.type === "video") {
    mediaHtml = `
      <video controls playsinline>
        <source src="${escapeHtml(payload.src)}" type="video/mp4">
      </video>
    `;
  } else if (payload.type === "youtube") {
    const id = parseYouTubeId(payload.src);
    const embed = id ? `https://www.youtube.com/embed/${id}` : "";
    mediaHtml = embed
      ? `<iframe src="${embed}" title="${escapeHtml(payload.title)}" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>`
      : `<div style="color:rgba(233,236,255,.75);padding:14px;border:1px solid rgba(255,255,255,.12);border-radius:16px;background:rgba(255,255,255,.04)">Invalid YouTube link.</div>`;
  } else {
    mediaHtml = `<div style="color:rgba(233,236,255,.75);padding:14px;border:1px solid rgba(255,255,255,.12);border-radius:16px;background:rgba(255,255,255,.04)">Unsupported item type.</div>`;
  }

  body.innerHTML = mediaHtml;

  const tags = payload.tags ? payload.tags.split(",").map(s => s.trim()).filter(Boolean) : [];
  const tagLine = tags.length ? `Tags: ${tags.map(escapeHtml).join(" • ")}` : "";
  const noteLine = payload.note ? escapeHtml(payload.note) : "";
  const linkLine = payload.type === "youtube" ? `Source: <a href="${escapeHtml(payload.src)}" target="_blank" rel="noopener noreferrer">${escapeHtml(payload.src)}</a>` : "";

  const parts = [noteLine, tagLine, linkLine].filter(Boolean);
  meta.innerHTML = parts.join("<br>");

  modal.setAttribute("aria-hidden", "false");
  document.body.style.overflow = "hidden";
}

function closeModal() {
  const modal = $("#modal");
  modal.setAttribute("aria-hidden", "true");
  $("#modalBody").innerHTML = "";
  document.body.style.overflow = "";
}

function wireCards() {
  const cards = document.querySelectorAll(".card");
  for (const c of cards) {
    const run = () => {
      openModal({
        type: c.dataset.type,
        title: c.dataset.title,
        src: c.dataset.src,
        note: c.dataset.note,
        tags: c.dataset.tags
      });
    };

    c.addEventListener("click", run);
    c.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        run();
      }
    });
  }
}

async function load() {
  try {
    const res = await fetch("./data.json", { cache: "no-store" });
    if (!res.ok) throw new Error("Failed to load data.json");
    state.data = await res.json();
  } catch {
    state.data = { title: "Work", sections: [] };
  }
  render();
}

function setup() {
  const search = $("#search");
  const toggle = $("#toggleView");

  search.addEventListener("input", () => {
    state.query = search.value || "";
    render();
  });

  toggle.addEventListener("click", () => {
    state.compact = !state.compact;
    document.body.classList.toggle("compact", state.compact);
    toggle.textContent = state.compact ? "Normal view" : "Compact view";
    toggle.setAttribute("aria-pressed", String(state.compact));
  });

  $("#modalClose").addEventListener("click", closeModal);
  $("#modalX").addEventListener("click", closeModal);
  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeModal();
  });

  load();
}

setup();
