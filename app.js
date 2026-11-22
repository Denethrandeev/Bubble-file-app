const files = [
  { name: "Projects", type: "folder", kind: "folder", size: "12 items", modified: "Today", favorite: true, quick: true },
  { name: "Presentation.pdf", type: "PDF", kind: "pdf", size: "8.4 MB", modified: "Today", favorite: true, quick: true },
  { name: "Vacation photos", type: "folder", kind: "folder", size: "86 items", modified: "Yesterday", favorite: false, quick: true },
  { name: "Travel.mp4", type: "MP4", kind: "video", size: "124 MB", modified: "Nov 18", favorite: false, quick: true },
  { name: "Product brief.docx", type: "DOCX", kind: "doc", size: "2.1 MB", modified: "Nov 20", favorite: true },
  { name: "Logo.png", type: "PNG", kind: "image", size: "3.8 MB", modified: "Nov 19", favorite: false },
  { name: "Archive.zip", type: "ZIP", kind: "zip", size: "42 MB", modified: "Nov 17", favorite: false },
  { name: "Budget.xlsx", type: "XLSX", kind: "doc", size: "890 KB", modified: "Nov 16", favorite: false },
  { name: "Family", type: "folder", kind: "folder", size: "31 items", modified: "Nov 14", favorite: true },
  { name: "Invoice.pdf", type: "PDF", kind: "pdf", size: "640 KB", modified: "Nov 12", favorite: false },
];

let currentView = "home";
let layout = "grid";
let sortDescending = false;
let uploadedBytes = 0;

const els = {
  quickGrid: document.querySelector("#quickGrid"),
  fileGrid: document.querySelector("#fileGrid"),
  fileCount: document.querySelector("#fileCount"),
  viewTitle: document.querySelector("#viewTitle"),
  viewEyebrow: document.querySelector("#viewEyebrow"),
  searchInput: document.querySelector("#searchInput"),
  newMenu: document.querySelector("#newMenu"),
  modalBackdrop: document.querySelector("#modalBackdrop"),
  folderName: document.querySelector("#folderName"),
  fileInput: document.querySelector("#fileInput"),
  toast: document.querySelector("#toast"),
  sidebar: document.querySelector("#sidebar"),
  sidebarScrim: document.querySelector("#sidebarScrim"),
};

function iconFor(file) {
  const labels = { folder: "▰", pdf: "PDF", image: "IMG", doc: "DOC", zip: "ZIP", video: "▶" };
  return labels[file.kind] || "FILE";
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;"
  }[char]));
}

function visibleFiles() {
  const query = els.searchInput.value.trim().toLowerCase();
  let result = files.filter((file) => {
    if (query && !file.name.toLowerCase().includes(query)) return false;
    if (currentView === "recent") return file.modified === "Today" || file.modified === "Yesterday";
    if (currentView === "favorites") return file.favorite;
    if (currentView === "trash") return file.trashed;
    if (currentView === "shared") return file.shared;
    return !file.trashed;
  });
  result = [...result].sort((a, b) => {
    const result = a.name.localeCompare(b.name);
    return sortDescending ? -result : result;
  });
  return result;
}

function render() {
  const quick = files.filter((file) => file.quick && !file.trashed).slice(0, 4);
  els.quickGrid.innerHTML = quick.map((file, index) => `
    <article class="quick-card" data-name="${escapeHtml(file.name)}">
      <div class="file-type-icon ${file.kind}">${iconFor(file)}</div>
      <button class="card-more" type="button" aria-label="More actions">•••</button>
      <strong>${escapeHtml(file.name)}</strong>
      <small>${escapeHtml(file.size)} · ${escapeHtml(file.modified)}</small>
    </article>
  `).join("");

  const visible = visibleFiles();
  els.fileGrid.className = `file-grid${layout === "list" ? " list-layout" : ""}`;
  els.fileGrid.innerHTML = visible.map((file) => `
    <article class="file-card" data-name="${escapeHtml(file.name)}">
      <div class="file-type-icon ${file.kind}">${iconFor(file)}</div>
      <button class="favorite ${file.favorite ? "active" : ""}" type="button" aria-label="Favorite">${file.favorite ? "★" : "☆"}</button>
      <div class="file-card-copy">
        <strong>${escapeHtml(file.name)}</strong>
        <small>${escapeHtml(file.type)}</small>
        <small>${escapeHtml(file.size)} · ${escapeHtml(file.modified)}</small>
      </div>
    </article>
  `).join("") || `<div class="empty-state"><strong>No files found</strong><small>Try another search or add a new file.</small></div>`;

  els.fileCount.textContent = `${visible.length} ${visible.length === 1 ? "item" : "items"}`;
  document.querySelector("#quickSection").style.display = currentView === "home" && !els.searchInput.value ? "" : "none";
}

function showToast(message) {
  els.toast.textContent = message;
  els.toast.classList.add("visible");
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => els.toast.classList.remove("visible"), 2300);
}

function setView(view) {
  currentView = view;
  const labels = {
    home: ["Personal storage", "My files", "All files"],
    recent: ["Your activity", "Recent", "Recently opened"],
    shared: ["With you", "Shared", "Shared files"],
    favorites: ["Saved items", "Favorites", "Favorite files"],
    trash: ["Recoverable items", "Trash", "Deleted files"],
  };
  const [eyebrow, title, section] = labels[view];
  els.viewEyebrow.textContent = eyebrow;
  els.viewTitle.textContent = title;
  document.querySelector("#fileSectionTitle").textContent = section;
  els.searchInput.placeholder = `Search in ${title}`;
  document.querySelectorAll(".nav-item").forEach((button) => button.classList.toggle("active", button.dataset.view === view));
  els.sidebar.classList.remove("open");
  els.sidebarScrim.classList.remove("visible");
  render();
}

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => setView(button.dataset.view));
});

els.searchInput.addEventListener("input", render);
document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    els.searchInput.focus();
  }
  if (event.key === "Escape") {
    els.newMenu.hidden = true;
    els.modalBackdrop.hidden = true;
  }
});

document.querySelector("#themeButton").addEventListener("click", () => {
  document.body.classList.toggle("dark");
  document.querySelector("#themeButton").textContent = document.body.classList.contains("dark") ? "☀" : "☾";
});

document.querySelectorAll(".view-toggle button").forEach((button) => {
  button.addEventListener("click", () => {
    layout = button.dataset.layout;
    document.querySelectorAll(".view-toggle button").forEach((item) => item.classList.toggle("active", item === button));
    render();
  });
});

document.querySelector("#sortButton").addEventListener("click", () => {
  sortDescending = !sortDescending;
  showToast(sortDescending ? "Sorted Z to A" : "Sorted A to Z");
  render();
});

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
els.fileInput.addEventListener("change", () => addUploadedFiles([...els.fileInput.files]));

function addUploadedFiles(selectedFiles) {
  selectedFiles.forEach((file) => {
    const extension = file.name.includes(".") ? file.name.split(".").pop().toUpperCase() : "FILE";
    const kind = file.type.startsWith("image/") ? "image" : file.type.startsWith("video/") ? "video" : ["PDF"].includes(extension) ? "pdf" : ["ZIP", "RAR", "7Z"].includes(extension) ? "zip" : ["DOC", "DOCX", "TXT", "XLS", "XLSX"].includes(extension) ? "doc" : "doc";
    const size = file.size >= 1024 * 1024 ? `${(file.size / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(file.size / 1024))} KB`;
    uploadedBytes += file.size;
    files.unshift({ name: file.name, type: extension, kind, size, modified: "Just now", favorite: false });
  });
  updateUploadedStorage();
  els.fileInput.value = "";
  setView("home");
  showToast(selectedFiles.length ? `${selectedFiles.length} file${selectedFiles.length === 1 ? "" : "s"} uploaded` : "No files selected");
}

function updateUploadedStorage() {
  const extraGb = uploadedBytes / 1024 / 1024 / 1024;
  const used = Math.min(100, 48.2 + extraGb);
  document.querySelector("#storageUsed").textContent = `${used.toFixed(1)} GB`;
  document.querySelector("#storagePercent").textContent = `${Math.round(used)}%`;
  document.querySelector("#storageFill").style.width = `${used}%`;
}

document.querySelector("#folderButton").addEventListener("click", () => {
  els.newMenu.hidden = true;
  els.modalBackdrop.hidden = false;
  els.folderName.value = "Untitled folder";
  requestAnimationFrame(() => els.folderName.select());
});
document.querySelector("#cancelFolder").addEventListener("click", () => { els.modalBackdrop.hidden = true; });
document.querySelector("#folderForm").addEventListener("submit", (event) => {
  event.preventDefault();
  const name = els.folderName.value.trim();
  if (!name) return;
  files.unshift({
    name,
    type: "folder",
    kind: "folder",
    size: "0 items",
    modified: "Just now",
    favorite: false,
  });
  els.modalBackdrop.hidden = true;
  setView("home");
  showToast(`Folder "${name}" created`);
});

els.modalBackdrop.addEventListener("click", (event) => {
  if (event.target === els.modalBackdrop) els.modalBackdrop.hidden = true;
});

els.fileGrid.addEventListener("click", (event) => {
  const favorite = event.target.closest(".favorite");
  if (favorite) {
    event.stopPropagation();
    const card = favorite.closest(".file-card");
    const file = files.find((item) => item.name === card?.dataset.name);
    if (file) {
      file.favorite = !file.favorite;
      render();
      showToast(file.favorite ? `"${file.name}" added to favorites` : `"${file.name}" removed from favorites`);
    }
    return;
  }
  const card = event.target.closest(".file-card");
  if (card) showToast(`Opened ${card.dataset.name}`);
});

els.quickGrid.addEventListener("click", (event) => {
  if (event.target.closest(".card-more")) {
    event.stopPropagation();
    showToast("File actions are ready");
    return;
  }
  const card = event.target.closest(".quick-card");
  if (card) showToast(`Opened ${card.dataset.name}`);
});

document.querySelector("#viewAllButton").addEventListener("click", () => setView("home"));
document.querySelector("#upgradeButton").addEventListener("click", () => showToast("Storage plans are coming soon"));
document.querySelector("#profileButton").addEventListener("click", () => showToast("Personal account"));

document.querySelector("#menuButton").addEventListener("click", () => {
  els.sidebar.classList.add("open");
  els.sidebarScrim.classList.add("visible");
});
els.sidebarScrim.addEventListener("click", () => {
  els.sidebar.classList.remove("open");
  els.sidebarScrim.classList.remove("visible");
});

const dropOverlay = document.querySelector("#dropOverlay");
["dragenter", "dragover"].forEach((name) => {
  document.addEventListener(name, (event) => {
    event.preventDefault();
    dropOverlay.classList.add("visible");
  });
});
["dragleave", "drop"].forEach((name) => {
  document.addEventListener(name, (event) => {
    event.preventDefault();
  });
});
document.addEventListener("dragenter", () => dropOverlay.classList.add("visible"));
document.addEventListener("dragleave", (event) => {
  if (event.relatedTarget === null) dropOverlay.classList.remove("visible");
});
document.addEventListener("drop", (event) => {
  dropOverlay.classList.remove("visible");
  if (event.dataTransfer?.files?.length) addUploadedFiles([...event.dataTransfer.files]);
});

render();
