const DB_NAME = "bubble-file-manager";
const DB_VERSION = 1;
const STORE_NAME = "items";
const MAX_TEXT_PREVIEW_BYTES = 1024 * 1024;
const TEXT_EXTENSIONS = new Set([
  "txt", "md", "markdown", "csv", "tsv", "json", "xml", "html", "htm",
  "css", "js", "mjs", "cjs", "ts", "tsx", "jsx", "py", "dart", "java",
  "kt", "kts", "c", "h", "cpp", "go", "rs", "sh", "yaml", "yml", "toml",
  "ini", "log", "sql", "graphql", "svg",
]);

let database;
let items = [];
let currentView = "home";
let currentFolderId = null;
let layout = readEnumPreference("layout", ["grid", "list"], "grid");
let sortMode = readEnumPreference("sortMode", ["name", "type", "size", "date"], "name");
let typeFilter = readEnumPreference("typeFilter", ["all", "folder", "image", "video", "audio", "document", "other"], "all");
let sortDescending = readPreference("sortDescending", "false") === "true";
let modalAction;
let previewObjectUrl;
let previewItemId;
let ready = false;

const els = {
  quickSection: document.querySelector("#quickSection"),
  quickGrid: document.querySelector("#quickGrid"),
  fileGrid: document.querySelector("#fileGrid"),
  fileCount: document.querySelector("#fileCount"),
  viewTitle: document.querySelector("#viewTitle"),
  viewEyebrow: document.querySelector("#viewEyebrow"),
  fileSectionTitle: document.querySelector("#fileSectionTitle"),
  breadcrumbs: document.querySelector("#breadcrumbs"),
  searchInput: document.querySelector("#searchInput"),
  sortSelect: document.querySelector("#sortSelect"),
  typeFilter: document.querySelector("#typeFilter"),
  sortDirection: document.querySelector("#sortDirection"),
  newMenu: document.querySelector("#newMenu"),
  modalBackdrop: document.querySelector("#modalBackdrop"),
  modalContent: document.querySelector("#modalContent"),
  fileInput: document.querySelector("#fileInput"),
  toast: document.querySelector("#toast"),
  sidebar: document.querySelector("#sidebar"),
  sidebarScrim: document.querySelector("#sidebarScrim"),
  previewBackdrop: document.querySelector("#previewBackdrop"),
  previewContent: document.querySelector("#previewContent"),
  workspaceNoticeText: document.querySelector("#workspaceNoticeText"),
};

function readPreference(key, fallback) {
  try {
    return localStorage.getItem(`bubble.${key}`) ?? fallback;
  } catch (error) {
    console.warn("Browser preferences are unavailable:", error);
    return fallback;
  }
}

function savePreference(key, value) {
  try {
    localStorage.setItem(`bubble.${key}`, value);
  } catch (error) {
    showToast(`Could not save this preference: ${error.message}`);
  }
}

function readEnumPreference(key, values, fallback) {
  const value = readPreference(key, fallback);
  return values.includes(value) ? value : fallback;
}

function openDatabase() {
  if (!("indexedDB" in window)) {
    return Promise.reject(new Error("This browser does not support persistent file storage."));
  }
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: "id" });
      }
    };
    request.onsuccess = () => {
      database = request.result;
      database.onversionchange = () => database.close();
      resolve(database);
    };
    request.onerror = () => reject(request.error || new Error("Could not open browser storage."));
    request.onblocked = () => reject(new Error("Browser storage is busy in another tab. Close other Bubble tabs and retry."));
  });
}

function readAllItems() {
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).getAll();
    let result = [];
    request.onsuccess = () => { result = request.result; };
    request.onerror = () => reject(request.error || new Error("Could not read the browser workspace."));
    transaction.oncomplete = () => resolve(result);
    transaction.onerror = () => reject(transaction.error || new Error("Could not read the browser workspace."));
    transaction.onabort = () => reject(transaction.error || new Error("Reading the browser workspace was cancelled."));
  });
}

function writeItems(putItems = [], deleteIds = []) {
  return new Promise((resolve, reject) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    const store = transaction.objectStore(STORE_NAME);
    putItems.forEach((item) => store.put(item));
    deleteIds.forEach((id) => store.delete(id));
    transaction.oncomplete = resolve;
    transaction.onerror = () => reject(transaction.error || new Error("Could not save changes to browser storage."));
    transaction.onabort = () => reject(transaction.error || new Error("Saving to browser storage was cancelled."));
  });
}

function createId() {
  return globalThis.crypto?.randomUUID ? globalThis.crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  }[char]));
}

function extensionOf(name) {
  const index = name.lastIndexOf(".");
  return index > 0 ? name.slice(index + 1).toLowerCase() : "";
}

function hasDragType(dataTransfer, type) {
  return Array.from(dataTransfer?.types || []).includes(type);
}

function kindFor(mime, name) {
  const extension = extensionOf(name);
  if (mime.startsWith("image/") || ["avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"].includes(extension)) return "image";
  if (mime.startsWith("audio/") || ["aac", "flac", "m4a", "m4b", "mp3", "oga", "ogg", "opus", "wav", "weba", "wma"].includes(extension)) return "audio";
  if (mime.startsWith("video/") || ["3gp", "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "ogv", "webm"].includes(extension)) return "video";
  if (mime === "application/pdf" || extension === "pdf") return "pdf";
  if (["zip", "rar", "7z", "gz", "tar"].includes(extension)) return "zip";
  if (["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods"].includes(extension)) return "doc";
  return "file";
}

function iconFor(item) {
  if (item.kind === "folder") return "▰";
  if (item.kind === "image") return "IMG";
  if (item.kind === "audio") return "♫";
  if (item.kind === "video") return "▶";
  if (item.kind === "pdf") return "PDF";
  if (item.kind === "zip") return "ZIP";
  if (item.kind === "doc") return "DOC";
  return (item.type || "FILE").slice(0, 4);
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / 1024 ** index;
  return `${value.toFixed(index === 0 || value >= 10 ? 0 : 1)} ${units[index]}`;
}

function formatDate(timestamp) {
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(timestamp));
}

function showToast(message) {
  els.toast.textContent = message;
  els.toast.classList.add("visible");
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => els.toast.classList.remove("visible"), 2800);
}

function findItem(id) {
  return items.find((item) => item.id === id);
}

function isInTrash(item) {
  let current = item;
  const seen = new Set();
  while (current && !seen.has(current.id)) {
    if (current.trashed) return true;
    seen.add(current.id);
    current = current.parentId ? findItem(current.parentId) : null;
  }
  return false;
}

function descendantsOf(rootId) {
  const result = [];
  const pending = [rootId];
  while (pending.length) {
    const parentId = pending.pop();
    const children = items.filter((item) => item.parentId === parentId);
    result.push(...children);
    pending.push(...children.filter((item) => item.kind === "folder").map((item) => item.id));
  }
  return result;
}

function folderPath(folderId) {
  const path = [];
  let folder = findItem(folderId);
  const seen = new Set();
  while (folder && folder.kind === "folder" && !seen.has(folder.id)) {
    path.unshift(folder);
    seen.add(folder.id);
    folder = folder.parentId ? findItem(folder.parentId) : null;
  }
  return path;
}

function setView(view) {
  currentView = view;
  currentFolderId = null;
  const labels = {
    home: ["Browser workspace", "My files", "All files"],
    recent: ["Browser workspace", "Recent", "Recently changed"],
    favorites: ["Browser workspace", "Favorites", "Favorite items"],
    trash: ["Browser workspace", "Trash", "Deleted items"],
  };
  const [eyebrow, title, section] = labels[view];
  els.viewEyebrow.textContent = eyebrow;
  els.viewTitle.textContent = title;
  els.fileSectionTitle.textContent = section;
  els.searchInput.placeholder = `Search ${view === "home" ? "this workspace" : title.toLowerCase()}`;
  document.querySelectorAll(".nav-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.view === view);
  });
  els.sidebar.classList.remove("open");
  els.sidebarScrim.classList.remove("visible");
  render();
}

function getVisibleItems() {
  const query = els.searchInput.value.trim().toLocaleLowerCase();
  let visible;
  if (currentView === "trash") {
    visible = items.filter((item) => item.trashed && (!query || item.name.toLocaleLowerCase().includes(query)));
  } else {
    visible = items.filter((item) => !isInTrash(item));
    if (currentView === "favorites") visible = visible.filter((item) => item.favorite);
    else if (currentView === "recent") {
      if (!query) visible = visible.sort((a, b) => b.modifiedAt - a.modifiedAt).slice(0, 20);
    }
    if (query) {
      visible = visible.filter((item) => `${item.name} ${item.type} ${item.mime}`.toLocaleLowerCase().includes(query));
    } else if (currentView === "home") {
      visible = visible.filter((item) => item.parentId === currentFolderId);
    }
  }

  if (typeFilter !== "all") {
    const documentTypes = new Set(["doc", "pdf"]);
    visible = visible.filter((item) => {
      if (typeFilter === "folder") return item.kind === "folder";
      if (typeFilter === "document") return documentTypes.has(item.kind);
      if (typeFilter === "other") return item.kind === "file" || item.kind === "zip";
      return item.kind === typeFilter;
    });
  }

  const direction = sortDescending ? -1 : 1;
  visible.sort((a, b) => {
    let result = 0;
    if (sortMode === "type") {
      result = (a.kind === "folder" ? "folder" : a.type).localeCompare(b.kind === "folder" ? "folder" : b.type);
    } else if (sortMode === "size") {
      result = (a.size || 0) - (b.size || 0);
    } else if (sortMode === "date") {
      result = a.modifiedAt - b.modifiedAt;
    } else {
      result = a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
    }
    if (sortMode !== "name" && (a.kind === "folder") !== (b.kind === "folder")) {
      return a.kind === "folder" ? -1 : 1;
    }
    return result * direction;
  });
  return visible;
}

function renderBreadcrumbs() {
  const query = els.searchInput.value.trim();
  if (currentView !== "home" || query) {
    els.breadcrumbs.innerHTML = query && currentView === "home"
      ? `<span>Search results across this browser workspace</span>`
      : "";
    return;
  }
  const path = folderPath(currentFolderId);
  els.breadcrumbs.innerHTML = [
    `<button type="button" data-folder="">My files</button>`,
    ...path.flatMap((folder, index) => [
      `<span aria-hidden="true">/</span>`,
      `<button type="button" data-folder="${escapeHtml(folder.id)}" ${index === path.length - 1 ? 'aria-current="page"' : ""}>${escapeHtml(folder.name)}</button>`,
    ]),
  ].join("");
}

function renderCard(item, quick = false) {
  const description = item.kind === "folder"
    ? `${items.filter((child) => child.parentId === item.id && !isInTrash(child)).length} items · Folder`
    : `${formatBytes(item.size)} · ${formatDate(item.modifiedAt)}`;
  const folderPathText = currentView !== "home" || els.searchInput.value.trim()
    ? folderPath(item.parentId).map((part) => part.name).join(" / ")
    : "";
  const iconClass = item.kind === "folder" ? "folder" : item.kind;
  if (quick) {
    return `<article class="quick-card" data-id="${escapeHtml(item.id)}" tabindex="0">
      <div class="file-type-icon ${iconClass}">${escapeHtml(iconFor(item))}</div>
      <strong>${escapeHtml(item.name)}</strong>
      <small>${escapeHtml(description)}</small>
    </article>`;
  }

  const actions = currentView === "trash"
    ? `<button type="button" data-action="restore">Restore</button><button type="button" data-action="purge" class="danger">Delete permanently</button>`
    : `<button type="button" data-action="open">Open / preview</button>
       ${item.kind !== "folder" ? '<button type="button" data-action="download">Download</button>' : ""}
       <button type="button" data-action="rename">Rename</button>
       <button type="button" data-action="move">Move to…</button>
       <button type="button" data-action="copy">Make a copy</button>
       <button type="button" data-action="favorite">${item.favorite ? "Remove favorite" : "Add favorite"}</button>
       <button type="button" data-action="trash" class="danger">Move to trash</button>`;

  return `<article class="file-card" data-id="${escapeHtml(item.id)}" draggable="true" tabindex="0">
    <div class="file-type-icon ${iconClass}">${escapeHtml(iconFor(item))}</div>
    <button class="favorite ${item.favorite ? "active" : ""}" type="button" data-action="favorite" aria-label="${item.favorite ? "Remove from" : "Add to"} favorites">${item.favorite ? "★" : "☆"}</button>
    <div class="file-card-copy">
      <strong>${escapeHtml(item.name)}</strong>
      <small>${escapeHtml(item.kind === "folder" ? "Folder" : item.type || "File")}${folderPathText ? ` · ${escapeHtml(folderPathText)}` : ""}</small>
      <small>${escapeHtml(description)}</small>
    </div>
    <details class="file-action"><summary aria-label="Actions for ${escapeHtml(item.name)}">•••</summary><div class="file-action-menu">${actions}</div></details>
  </article>`;
}

function renderStorageSummary() {
  const activeItems = items.filter((item) => !isInTrash(item));
  const totalBytes = activeItems.reduce((sum, item) => sum + (item.kind === "folder" ? 0 : item.size || 0), 0);
  document.querySelector("#storageCount").textContent = `${activeItems.length} ${activeItems.length === 1 ? "item" : "items"}`;
  document.querySelector("#storageUsed").textContent = formatBytes(totalBytes);
}

function render() {
  const query = els.searchInput.value.trim();
  if (query && currentView === "home") currentFolderId = null;
  const activeFolder = currentView === "home" ? findItem(currentFolderId) : null;
  if (activeFolder?.trashed || (currentFolderId && !activeFolder)) currentFolderId = null;
  if (currentView === "home") {
    els.viewTitle.textContent = currentFolderId ? findItem(currentFolderId)?.name || "My files" : "My files";
  }
  renderBreadcrumbs();

  const recent = items
    .filter((item) => !isInTrash(item))
    .sort((a, b) => b.modifiedAt - a.modifiedAt)
    .slice(0, 4);
  const showQuick = currentView === "home" && !query && !currentFolderId && recent.length > 0;
  els.quickSection.style.display = showQuick ? "" : "none";
  if (showQuick) els.quickGrid.innerHTML = recent.map((item) => renderCard(item, true)).join("");

  const visible = getVisibleItems();
  els.fileGrid.className = `file-grid${layout === "list" ? " list-layout" : ""}`;
  if (!ready) {
    els.fileGrid.innerHTML = `<div class="empty-state"><strong>Loading browser workspace…</strong></div>`;
  } else if (!visible.length) {
    const emptyTitle = currentView === "trash" ? "Trash is empty"
      : currentView === "favorites" ? "No favorites yet"
        : currentView === "recent" ? "No recent items"
          : query || typeFilter !== "all" ? "No items match these filters" : "This folder is empty";
    const emptyDescription = currentView === "trash" ? "Deleted items will appear here." : "Create a folder or add files to this browser workspace.";
    const emptyActions = currentView === "trash" ? "" : `<div class="empty-actions"><button type="button" data-empty-action="folder">New folder</button><button type="button" data-empty-action="upload">Upload files</button></div>`;
    els.fileGrid.innerHTML = `<div class="empty-state"><strong>${emptyTitle}</strong><small>${emptyDescription}</small>${emptyActions}</div>`;
  } else {
    els.fileGrid.innerHTML = visible.map((item) => renderCard(item)).join("");
  }
  els.fileCount.textContent = `${visible.length} ${visible.length === 1 ? "item" : "items"}`;
  document.querySelectorAll(".view-toggle button").forEach((button) => {
    button.classList.toggle("active", button.dataset.layout === layout);
  });
  els.sortSelect.value = sortMode;
  els.typeFilter.value = typeFilter;
  els.sortDirection.textContent = sortDescending ? "↓" : "↑";
  els.sortDirection.setAttribute("aria-label", sortDescending ? "Sort descending" : "Sort ascending");
  renderStorageSummary();

}

function updateCardOpen(item) {
  if (item.kind === "folder") {
    if (currentView !== "home" || els.searchInput.value.trim()) setView("home");
    currentFolderId = item.id;
    els.searchInput.value = "";
    render();
    return;
  }
  openPreview(item).catch((error) => showToast(`Could not preview file: ${error.message}`));
}

function openModal({ title, description = "", fields = "", submitLabel = "Save", danger = false, action }) {
  modalAction = action;
  els.modalContent.innerHTML = `<h2>${escapeHtml(title)}</h2>
    ${description ? `<p class="modal-description">${escapeHtml(description)}</p>` : ""}
    ${fields}
    <p class="modal-error" id="modalError" role="alert"></p>
    <div class="modal-actions"><button type="button" id="cancelModal">Cancel</button><button type="submit" class="${danger ? "danger" : "primary"}">${escapeHtml(submitLabel)}</button></div>`;
  els.modalBackdrop.hidden = false;
  document.querySelector("#cancelModal").addEventListener("click", closeModal);
  els.modalContent.querySelector("input, select")?.focus();
}

function closeModal() {
  els.modalBackdrop.hidden = true;
  modalAction = null;
}

function showFolderModal() {
  const parentId = currentView === "home" ? currentFolderId : null;
  openModal({
    title: "Create new folder",
    fields: `<label for="modalName">Folder name<input id="modalName" name="name" type="text" maxlength="120" required /></label>`,
    submitLabel: "Create folder",
    action: async (form) => {
      const name = form.get("name").trim();
      if (!name) throw new Error("Enter a folder name.");
      if (items.some((item) => item.parentId === parentId && !item.trashed && item.name.toLocaleLowerCase() === name.toLocaleLowerCase())) {
        throw new Error("An item with that name already exists here.");
      }
      const folder = {
        id: createId(), name, parentId, kind: "folder", type: "Folder", mime: "",
        size: 0, modifiedAt: Date.now(), favorite: false, trashed: false, blob: null,
      };
      await writeItems([folder]);
      items.push(folder);
      setView("home");
      currentFolderId = parentId;
      render();
      showToast(`Created folder "${name}"`);
    },
  });
}

function uniqueName(name, parentId, excludedIds = new Set(), reservedNames = new Set()) {
  const available = (candidate) => !items.some((item) =>
    item.parentId === parentId && !isInTrash(item) && !excludedIds.has(item.id)
    && item.name.toLocaleLowerCase() === candidate.toLocaleLowerCase())
    && !reservedNames.has(candidate.toLocaleLowerCase());
  if (available(name)) return name;
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name;
  const suffix = dot > 0 ? name.slice(dot) : "";
  let index = 1;
  while (!available(`${stem} (${index})${suffix}`)) index++;
  return `${stem} (${index})${suffix}`;
}

function showRenameModal(item) {
  openModal({
    title: "Rename item",
    fields: `<label for="modalName">Name<input id="modalName" name="name" type="text" maxlength="180" value="${escapeHtml(item.name)}" required /></label>`,
    submitLabel: "Rename",
    action: async (form) => {
      const name = form.get("name").trim();
      if (!name) throw new Error("Enter a name.");
      if (items.some((other) => other.id !== item.id && other.parentId === item.parentId && !isInTrash(other) && other.name.toLocaleLowerCase() === name.toLocaleLowerCase())) {
        throw new Error("An item with that name already exists here.");
      }
      const updated = { ...item, name, type: item.kind === "folder" ? "Folder" : (extensionOf(name).toUpperCase() || "File"), modifiedAt: Date.now() };
      await writeItems([updated]);
      items = items.map((entry) => entry.id === item.id ? updated : entry);
      render();
      showToast("Item renamed");
    },
  });
}

function canMoveTo(item, parentId) {
  if (item.id === parentId) return false;
  let parent = parentId ? findItem(parentId) : null;
  while (parent) {
    if (parent.id === item.id) return false;
    parent = parent.parentId ? findItem(parent.parentId) : null;
  }
  return true;
}

function showTransferModal(item, mode) {
  const folderOptions = items
    .filter((entry) => entry.kind === "folder" && !isInTrash(entry) && canMoveTo(item, entry.id))
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((folder) => `<option value="${escapeHtml(folder.id)}">${escapeHtml(folderPath(folder.parentId).map((part) => part.name).concat(folder.name).join(" / "))}</option>`)
    .join("");
  openModal({
    title: mode === "move" ? "Move item" : "Make a copy",
    description: mode === "copy" ? "A separate browser-stored copy will be created in the selected folder." : "Choose a destination folder. The root option moves the item to My files.",
    fields: `<label for="modalTarget">Destination folder<select id="modalTarget" name="parentId"><option value="">My files (root)</option>${folderOptions}</select></label>`,
    submitLabel: mode === "move" ? "Move" : "Copy",
    action: async (form) => {
      const parentId = form.get("parentId") || null;
      if (!canMoveTo(item, parentId)) throw new Error("A folder cannot be moved into itself or one of its subfolders.");
      if (mode === "move" && item.parentId === parentId) throw new Error("This item is already in that folder.");
      if (mode === "move") {
        const updated = { ...item, parentId, name: uniqueName(item.name, parentId, new Set([item.id])), modifiedAt: Date.now() };
        await writeItems([updated]);
        items = items.map((entry) => entry.id === item.id ? updated : entry);
      } else {
        const sourceTree = [item, ...descendantsOf(item.id)];
        const idMap = new Map(sourceTree.map((entry) => [entry.id, createId()]));
        const rootName = uniqueName(`Copy of ${item.name}`, parentId);
        const copies = sourceTree.map((entry) => ({
          ...entry,
          id: idMap.get(entry.id),
          name: entry.id === item.id ? rootName : entry.name,
          parentId: entry.id === item.id ? parentId : idMap.get(entry.parentId),
          modifiedAt: Date.now(),
          trashed: false,
        }));
        await writeItems(copies);
        items.push(...copies);
      }
      render();
      showToast(mode === "move" ? "Item moved" : "Copy created");
    },
  });
}

function showConfirmModal(title, description, confirmLabel, action) {
  openModal({
    title,
    description,
    submitLabel: confirmLabel,
    danger: true,
    action,
  });
}

async function trashItem(item) {
  const updated = { ...item, trashed: true, modifiedAt: Date.now() };
  await writeItems([updated]);
  items = items.map((entry) => entry.id === item.id ? updated : entry);
  render();
  showToast(`Moved "${item.name}" to Trash`);
}

async function permanentlyDelete(item) {
  const remove = [item, ...descendantsOf(item.id)];
  await writeItems([], remove.map((entry) => entry.id));
  const ids = new Set(remove.map((entry) => entry.id));
  items = items.filter((entry) => !ids.has(entry.id));
  render();
  showToast("Item permanently deleted");
}

async function restoreItem(item) {
  let parentId = item.parentId;
  if (parentId && (!findItem(parentId) || isInTrash(findItem(parentId)))) parentId = null;
  const restored = { ...item, parentId, trashed: false, modifiedAt: Date.now() };
  restored.name = uniqueName(restored.name, parentId, new Set([item.id]));
  await writeItems([restored]);
  items = items.map((entry) => entry.id === item.id ? restored : entry);
  render();
  showToast("Item restored");
}

function downloadItem(item) {
  if (!item.blob) {
    showToast("This item has no browser-stored file data to download.");
    return;
  }
  const url = URL.createObjectURL(item.blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = item.name;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function isTextFile(item) {
  return item.mime.startsWith("text/") || /json|xml|javascript|yaml|sql/.test(item.mime)
    || TEXT_EXTENSIONS.has(extensionOf(item.name));
}

async function openPreview(item) {
  if (!item.blob) {
    showToast("This item has no browser-stored file data.");
    return;
  }
  if (previewObjectUrl) URL.revokeObjectURL(previewObjectUrl);
  previewObjectUrl = URL.createObjectURL(item.blob);
  previewItemId = item.id;
  document.querySelector("#previewTitle").textContent = item.name;
  document.querySelector("#previewDetails").textContent = [
    item.type || item.mime || "File",
    formatBytes(item.size),
    `Added ${formatDate(item.modifiedAt)}`,
  ].join(" · ");
  els.previewContent.replaceChildren();

  if (item.kind === "image") {
    const image = document.createElement("img");
    image.alt = item.name;
    image.src = previewObjectUrl;
    els.previewContent.append(image);
  } else if (item.kind === "audio" || item.kind === "video") {
    const player = document.createElement(item.kind);
    player.controls = true;
    player.preload = "metadata";
    player.src = previewObjectUrl;
    player.addEventListener("loadedmetadata", () => {
      const duration = Number.isFinite(player.duration) ? `${Math.floor(player.duration / 60)}:${String(Math.floor(player.duration % 60)).padStart(2, "0")}` : "Unknown duration";
      document.querySelector("#previewDetails").textContent += ` · ${duration}`;
    }, { once: true });
    els.previewContent.append(player);
  } else if (isTextFile(item)) {
    if (item.size > MAX_TEXT_PREVIEW_BYTES) {
      els.previewContent.innerHTML = `<p class="preview-message">This text file is larger than ${formatBytes(MAX_TEXT_PREVIEW_BYTES)}. Download it to view the full contents.</p>`;
    } else {
      const pre = document.createElement("pre");
      pre.textContent = await item.blob.text();
      els.previewContent.append(pre);
    }
  } else if (item.mime === "application/pdf" || extensionOf(item.name) === "pdf") {
    const frame = document.createElement("iframe");
    frame.title = `Preview of ${item.name}`;
    frame.src = previewObjectUrl;
    els.previewContent.append(frame);
  } else {
    const message = document.createElement("p");
    message.className = "preview-message";
    message.textContent = `Preview is not available for this file type (${item.mime || item.type}). You can still download the file.`;
    els.previewContent.append(message);
  }
  els.previewBackdrop.hidden = false;
}

async function addFiles(fileList, destinationId = currentView === "home" ? currentFolderId : null) {
  const selected = [...fileList];
  if (!selected.length) return;
  const additions = [];
  const reservedNames = new Set();
  for (const file of selected) {
    const mime = file.type || "application/octet-stream";
    const name = uniqueName(file.name, destinationId, new Set(), reservedNames);
    reservedNames.add(name.toLocaleLowerCase());
    additions.push({
      id: createId(), name, parentId: destinationId, kind: kindFor(mime, name),
      type: extensionOf(name).toUpperCase() || mime.split("/").pop() || "FILE",
      mime, size: file.size, modifiedAt: Date.now(), favorite: false, trashed: false,
      blob: file,
    });
  }
  try {
    await writeItems(additions);
    items.push(...additions);
    els.fileInput.value = "";
    setView("home");
    currentFolderId = destinationId;
    render();
    showToast(`${additions.length} file${additions.length === 1 ? "" : "s"} added to this browser`);
  } catch (error) {
    els.fileInput.value = "";
    showToast(`Upload could not be saved in this browser: ${error.message}`);
  }
}

function handleItemAction(action, item) {
  if (!item) return;
  if (action === "open") updateCardOpen(item);
  else if (action === "download") downloadItem(item);
  else if (action === "rename") showRenameModal(item);
  else if (action === "move" || action === "copy") showTransferModal(item, action);
  else if (action === "favorite") {
    const updated = { ...item, favorite: !item.favorite };
    writeItems([updated]).then(() => {
      items = items.map((entry) => entry.id === item.id ? updated : entry);
      render();
    }).catch((error) => showToast(`Could not update favorite: ${error.message}`));
  } else if (action === "trash") {
    showConfirmModal("Move to Trash?", `"${item.name}" can be restored from Trash.`, "Move to Trash", async () => trashItem(item));
  } else if (action === "restore") {
    restoreItem(item).catch((error) => showToast(`Could not restore item: ${error.message}`));
  } else if (action === "purge") {
    showConfirmModal("Delete permanently?", `"${item.name}" and everything inside it will be permanently removed from this browser.`, "Delete permanently", async () => permanentlyDelete(item));
  }
}

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => setView(button.dataset.view));
});
document.querySelector("#viewAllButton").addEventListener("click", () => setView("recent"));

els.searchInput.addEventListener("input", render);
els.typeFilter.addEventListener("change", () => {
  typeFilter = els.typeFilter.value;
  savePreference("typeFilter", typeFilter);
  render();
});
els.sortSelect.addEventListener("change", () => {
  sortMode = els.sortSelect.value;
  savePreference("sortMode", sortMode);
  render();
});
els.sortDirection.addEventListener("click", () => {
  sortDescending = !sortDescending;
  savePreference("sortDescending", String(sortDescending));
  render();
});
document.querySelectorAll(".view-toggle button").forEach((button) => {
  button.addEventListener("click", () => {
    layout = button.dataset.layout;
    savePreference("layout", layout);
    render();
  });
});

document.querySelector("#themeButton").addEventListener("click", () => {
  const dark = document.body.classList.toggle("dark");
  document.querySelector("#themeButton").textContent = dark ? "☀" : "☾";
  savePreference("theme", dark ? "dark" : "light");
});
if (readPreference("theme", "light") === "dark") {
  document.body.classList.add("dark");
  document.querySelector("#themeButton").textContent = "☀";
}

document.querySelector("#newButton").addEventListener("click", (event) => {
  event.stopPropagation();
  els.newMenu.hidden = !els.newMenu.hidden;
});
document.addEventListener("click", (event) => {
  if (!els.newMenu.hidden && !els.newMenu.contains(event.target) && event.target.id !== "newButton") {
    els.newMenu.hidden = true;
  }
});
document.querySelector("#uploadButton").addEventListener("click", () => {
  els.newMenu.hidden = true;
  els.fileInput.click();
});
document.querySelector("#folderButton").addEventListener("click", () => {
  els.newMenu.hidden = true;
  showFolderModal();
});
els.fileInput.addEventListener("change", () => addFiles(els.fileInput.files));

document.querySelector("#folderForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!modalAction) return;
  const submit = els.modalContent.querySelector('button[type="submit"]');
  submit.disabled = true;
  try {
    await modalAction(new FormData(event.currentTarget));
    closeModal();
  } catch (error) {
    const errorElement = document.querySelector("#modalError");
    if (errorElement) errorElement.textContent = error.message;
  } finally {
    if (submit.isConnected) submit.disabled = false;
  }
});
els.modalBackdrop.addEventListener("click", (event) => {
  if (event.target === els.modalBackdrop) closeModal();
});

els.fileGrid.addEventListener("click", (event) => {
  const actionButton = event.target.closest("[data-action]");
  const card = event.target.closest(".file-card");
  if (actionButton && card) {
    event.preventDefault();
    event.stopPropagation();
    card.querySelector(".file-action")?.removeAttribute("open");
    handleItemAction(actionButton.dataset.action, findItem(card.dataset.id));
    return;
  }
  if (event.target.closest(".file-action")) return;
  const emptyAction = event.target.closest("[data-empty-action]");
  if (emptyAction) {
    if (emptyAction.dataset.emptyAction === "upload") els.fileInput.click();
    else showFolderModal();
    return;
  }
  if (card) updateCardOpen(findItem(card.dataset.id));
});
els.fileGrid.addEventListener("keydown", (event) => {
  if ((event.key === "Enter" || event.key === " ") && event.target.matches(".file-card")) {
    event.preventDefault();
    updateCardOpen(findItem(event.target.dataset.id));
  }
});
els.quickGrid.addEventListener("click", (event) => {
  const card = event.target.closest(".quick-card");
  if (card) updateCardOpen(findItem(card.dataset.id));
});
els.quickGrid.addEventListener("keydown", (event) => {
  if ((event.key === "Enter" || event.key === " ") && event.target.matches(".quick-card")) {
    event.preventDefault();
    updateCardOpen(findItem(event.target.dataset.id));
  }
});
els.breadcrumbs.addEventListener("click", (event) => {
  const button = event.target.closest("[data-folder]");
  if (!button) return;
  currentFolderId = button.dataset.folder || null;
  render();
});

els.fileGrid.addEventListener("dragstart", (event) => {
  const card = event.target.closest(".file-card");
  if (!card) return;
  event.dataTransfer.setData("application/x-bubble-item", card.dataset.id);
  event.dataTransfer.effectAllowed = "move";
});
els.fileGrid.addEventListener("dragover", (event) => {
  const card = event.target.closest(".file-card");
  if (card && findItem(card.dataset.id)?.kind === "folder" && hasDragType(event.dataTransfer, "application/x-bubble-item")) {
    event.preventDefault();
    card.classList.add("drag-target");
  } else if (hasDragType(event.dataTransfer, "Files")) {
    event.preventDefault();
  }
});
els.fileGrid.addEventListener("dragleave", (event) => {
  event.target.closest(".file-card")?.classList.remove("drag-target");
});
els.fileGrid.addEventListener("drop", (event) => {
  event.preventDefault();
  event.stopPropagation();
  dropOverlay.classList.remove("visible");
  const card = event.target.closest(".file-card");
  document.querySelectorAll(".drag-target").forEach((target) => target.classList.remove("drag-target"));
  const targetFolder = card && findItem(card.dataset.id)?.kind === "folder" ? findItem(card.dataset.id) : null;
  const movingId = event.dataTransfer.getData("application/x-bubble-item");
  if (movingId && targetFolder) {
    const item = findItem(movingId);
    if (item && canMoveTo(item, targetFolder.id)) {
      const updated = {
        ...item,
        parentId: targetFolder.id,
        name: uniqueName(item.name, targetFolder.id, new Set([item.id])),
        modifiedAt: Date.now(),
      };
      writeItems([updated]).then(() => {
        items = items.map((entry) => entry.id === updated.id ? updated : entry);
        render();
        showToast(`Moved into "${targetFolder.name}"`);
      }).catch((error) => showToast(`Move failed: ${error.message}`));
    } else {
      showToast("That move would create a folder loop.");
    }
  } else if (event.dataTransfer.files.length) {
    addFiles(event.dataTransfer.files, targetFolder?.id ?? (currentView === "home" ? currentFolderId : null));
  }
});

const dropOverlay = document.querySelector("#dropOverlay");
document.addEventListener("dragenter", (event) => {
  if (hasDragType(event.dataTransfer, "Files")) dropOverlay.classList.add("visible");
});
document.addEventListener("dragover", (event) => {
  if (hasDragType(event.dataTransfer, "Files")) {
    event.preventDefault();
    dropOverlay.classList.add("visible");
  }
});
document.addEventListener("dragleave", (event) => {
  if (event.relatedTarget === null) dropOverlay.classList.remove("visible");
});
document.addEventListener("drop", (event) => {
  dropOverlay.classList.remove("visible");
  if (event.dataTransfer?.files.length) {
    event.preventDefault();
    addFiles(event.dataTransfer.files);
  }
});

function closePreview() {
  els.previewBackdrop.hidden = true;
  els.previewContent.replaceChildren();
  if (previewObjectUrl) URL.revokeObjectURL(previewObjectUrl);
  previewObjectUrl = null;
  previewItemId = null;
}
document.querySelector("#closePreview").addEventListener("click", closePreview);
document.querySelector("#closePreviewFooter").addEventListener("click", closePreview);
els.previewBackdrop.addEventListener("click", (event) => {
  if (event.target === els.previewBackdrop) closePreview();
});
document.querySelector("#downloadPreview").addEventListener("click", () => {
  const item = findItem(previewItemId);
  if (item) downloadItem(item);
});

document.querySelector("#menuButton").addEventListener("click", () => {
  els.sidebar.classList.add("open");
  els.sidebarScrim.classList.add("visible");
});
els.sidebarScrim.addEventListener("click", () => {
  els.sidebar.classList.remove("open");
  els.sidebarScrim.classList.remove("visible");
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    els.searchInput.focus();
  }
  if (event.key === "Escape") {
    els.newMenu.hidden = true;
    closeModal();
    closePreview();
  }
});

async function initialize() {
  try {
    await openDatabase();
    items = await readAllItems();
    ready = true;
    if (els.workspaceNoticeText) {
      els.workspaceNoticeText.textContent = "Files you add are saved in this browser on this device. This web app does not access device storage automatically or sync with the Android app.";
    }
    render();
  } catch (error) {
    ready = true;
    if (els.workspaceNoticeText) {
      els.workspaceNoticeText.textContent = `Browser storage is unavailable: ${error.message} Enable site storage in your browser and reload.`;
    }
    render();
    showToast(`Could not open browser workspace: ${error.message}`);
  }
}

render();
initialize();
