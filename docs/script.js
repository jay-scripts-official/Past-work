const sections = [
  {
    title: "Combat Systems",
    items: [
      { type: "video", src: "assets/combat/combo.mp4" },
      { type: "image", src: "assets/combat/hitbox.png" }
    ]
  },
  {
    title: "UI Systems",
    items: [
      { type: "video", src: "assets/ui/inventory.mp4" }
    ]
  },
  {
    title: "Movement Systems",
    items: [
      { type: "video", src: "assets/movement/dash.mp4" }
    ]
  }
];

const portfolio = document.getElementById("portfolio");

sections.forEach(section => {
  const sec = document.createElement("section");
  sec.innerHTML = `<h2>${section.title}</h2>`;

  const grid = document.createElement("div");
  grid.className = "grid";

  section.items.forEach(item => {
    if (item.type === "video") {
      grid.innerHTML += `
        <video controls muted loop>
          <source src="${item.src}" type="video/mp4">
        </video>
      `;
    } else {
      grid.innerHTML += `<img src="${item.src}">`;
    }
  });

  sec.appendChild(grid);
  portfolio.appendChild(sec);
});
