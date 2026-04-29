const container = document.getElementById("container");
const fovEl = document.getElementById("fov");

let isCollapsed = false;

window.addEventListener("message", (e) => {
  const { type, data } = e.data;

  if (type === "show") {
    container.classList.remove("hidden");
    isCollapsed = false;
  } else if (type === "hide") {
    container.classList.add("hidden");
  } else if (type === "toggle") {
    isCollapsed = !isCollapsed;
    container.classList.toggle("collapsed", isCollapsed);
  } else if (type === "update") {
    if (data.fov !== undefined) fovEl.textContent = data.fov + "°";
  }
});
