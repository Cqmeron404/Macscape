const hero = document.querySelector("#preview");
const canvas = hero.querySelector("canvas");
const context = canvas.getContext("2d");
const choices = [...document.querySelectorAll("[data-effect]")];
const motion = document.querySelector("#motion");
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
let paused = reducedMotion.matches;
let visible = true;
let frame = 0;
let previous = 0;
let elapsed = 0;
let width = 0;
let height = 0;
let particles = [];
let pointer = null;

// Each preview shares the desktop geometry but has its own material and impact.
const styles = {
  snow: {speed:28, wind:5, color:"#fff", deposit:"#f3faff"},
  sakura: {speed:31, wind:15, color:"#ffc7df", deposit:"#ffc7df"},
  rain: {speed:230, wind:45, color:"#b9ddff"},
  fireflies: {speed:0, wind:0, color:"#ffe584"}
};
let surfaces = [];
let sparks = [];

function flake(randomHeight = false) {
  return {x:Math.random() * width, y:randomHeight ? Math.random() * height : -12,
    size:.8 + Math.random() * 1.5, phase:Math.random() * Math.PI * 2};
}

function drawDrifts(color) {
  for (const s of surfaces) {
    context.beginPath();
    context.moveTo(s.left, s.top);
    s.pile.forEach((depth, i) => context.lineTo(s.left + i * s.step, s.top - depth));
    context.lineTo(s.right, s.top + 1);
    context.closePath();
    context.fillStyle = color;
    context.fill();
  }
}

function impact(p, surface, index, effect) {
  if (effect.deposit) {
    for (let offset = -2; offset <= 2; offset++) {
      const bin = index + offset;
      if (bin > 0 && bin < surface.pile.length - 1) {
        surface.pile[bin] = Math.min(13, surface.pile[bin] + (3 - Math.abs(offset)) * .48);
      }
    }
  } else {
    for (let i = 0; i < 4; i++) {
      sparks.push({x:p.x, y:surface.top, vx:(Math.random() - .5) * 75,
        vy:-18 - Math.random() * 45, life:.38, color:effect.color});
    }
  }
}

function paint(seconds) {
  elapsed += seconds;
  const scene = hero.dataset.scene;
  const effect = styles[scene];
  context.clearRect(0, 0, width, height);
  if (effect.deposit) drawDrifts(effect.deposit);
  for (const p of particles) {
    const wave = Math.sin(elapsed + p.phase);
    const previousY = p.y;
    p.x += (effect.wind + wave * 13) * seconds;
    p.y += (effect.speed * p.size + (scene === "fireflies" ? wave * 13 : 0)) * seconds;
    if (scene === "fireflies" && pointer) {
      p.x += (pointer.x - p.x) * seconds * .065;
      p.y += (pointer.y - p.y) * seconds * .065;
    }
    let landed = false;
    for (const surface of surfaces) {
      if (p.x < surface.left || p.x >= surface.right || scene === "fireflies") continue;
      const index = Math.floor((p.x - surface.left) / surface.step);
      const top = surface.top - surface.pile[index];
      if (previousY <= top && p.y >= top) {
        impact(p, surface, index, effect);
        landed = true;
        break;
      }
    }
    if (landed || p.y > height + 10 || p.y < -20) {
      Object.assign(p, flake());
      continue;
    }
    if (p.x > width + 12) p.x = -10;
    if (p.x < -12) p.x = width + 10;
    context.beginPath();
    context.fillStyle = effect.color;
    if (scene === "rain") {
      context.moveTo(p.x, p.y);
      const length = 11;
      context.lineTo(p.x - length * effect.wind/effect.speed, p.y - length);
      context.strokeStyle = effect.color;
      context.stroke();
    } else {
      const petal = scene === "sakura";
      context.globalAlpha = scene === "fireflies" ? .55 + .4 * wave : .84;
      context.ellipse(p.x, p.y, p.size * (petal ? 2.7 : 1), p.size, elapsed + p.phase, 0, Math.PI * 2);
      context.fill();
      context.globalAlpha = 1;
    }
  }
  sparks = sparks.filter(s => s.life > 0);
  for (const s of sparks) {
    s.x += s.vx * seconds;
    s.y += s.vy * seconds;
    s.vy += 120 * seconds;
    s.life -= seconds;
    context.fillStyle = s.color;
    context.fillRect(s.x, s.y, 2, 2);
  }
}

function animate(now) {
  paint(previous ? Math.min(.05, (now - previous) / 1000) : 0);
  previous = now;
  frame = requestAnimationFrame(animate);
}

function updatePlayback() {
  cancelAnimationFrame(frame);
  previous = 0;
  motion.textContent = paused ? "▶" : "Ⅱ";
  motion.title = (paused ? "Play" : "Pause") + " preview animation";
  motion.setAttribute("aria-label", motion.title);
  if (!paused && visible && !document.hidden) frame = requestAnimationFrame(animate);
}

function resize() {
  width = hero.clientWidth;
  height = hero.clientHeight;
  const scale = Math.min(devicePixelRatio, 2);
  canvas.width = Math.round(width * scale);
  canvas.height = Math.round(height * scale);
  context.setTransform(scale, 0, 0, scale, 0, 0);
  const bounds = hero.getBoundingClientRect();
  surfaces = [hero.querySelector(".sample-window"), hero.querySelector(".dock")].map(element => {
    const rect = element.getBoundingClientRect();
    const left = rect.left - bounds.left + 7;
    const right = rect.right - bounds.left - 7;
    const bins = Math.max(2, Math.ceil((right-left)/4));
    const pile = Array.from({length:bins+1}, (_,i) => styles[hero.dataset.scene].deposit
      ? Math.sin(Math.PI*i/bins)*(3+1.5*Math.sin(i*.35)) : 0);
    return {left, right, top:rect.top-bounds.top, step:(right-left)/bins, pile};
  });
  particles = Array.from({length:Math.min(210, Math.ceil(width / 4))}, () => flake(true));
  sparks = [];
  paint(0);
}

function setScene(value) {
  hero.dataset.scene = value;
  choices.forEach(choice => choice.setAttribute("aria-pressed", String(choice.dataset.effect === value)));
  resize();
}
choices.forEach(choice => choice.addEventListener("click", () => setScene(choice.dataset.effect)));
document.querySelectorAll("[data-preview]").forEach(button => {
  button.addEventListener("click", () => {
    setScene(button.dataset.preview);
    hero.scrollIntoView({block:"start", behavior:reducedMotion.matches ? "instant" : "smooth"});
    choices.find(choice => choice.dataset.effect === button.dataset.preview).focus({preventScroll:true});
  });
});
hero.addEventListener("pointermove", event => {
  const bounds = hero.getBoundingClientRect();
  pointer = {x:event.clientX - bounds.left, y:event.clientY - bounds.top};
});
hero.addEventListener("pointerleave", () => { pointer = null; });
motion.addEventListener("click", () => { paused = !paused; updatePlayback(); });
reducedMotion.addEventListener("change", () => { paused = reducedMotion.matches; updatePlayback(); });
document.addEventListener("visibilitychange", updatePlayback);
new ResizeObserver(resize).observe(hero);
new IntersectionObserver(entries => { visible = entries[0].isIntersecting; updatePlayback(); }).observe(hero);
resize();
updatePlayback();

const downloadButtons = document.querySelectorAll("[data-download]");
const statuses = document.querySelectorAll(".status");
function announce(text) {
  statuses.forEach(status => { status.textContent = text; });
}

async function downloadApp() {
  downloadButtons.forEach(button => { button.disabled = true; });
  announce("Preparing Macscapes.zip…");
  try {
    const response = await fetch("Macscapes.zip.b64.txt");
    if (!response.ok) throw new Error("Download unavailable");
    const binary = atob((await response.text()).replace(/\s+/g, ""));
    const blob = new Blob([Uint8Array.from(binary, char => char.charCodeAt(0))], {type:"application/zip"});
    const downloads = window.claude?.use ? await window.claude.use("downloads") : null;
    if (downloads) {
      await downloads.save({filename:"Macscapes.zip", data:blob});
    } else {
      const link = document.createElement("a");
      const url = URL.createObjectURL(blob);
      link.href = url;
      link.download = "Macscapes.zip";
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    }
    announce("Download requested. Unzip Macscapes and move it to Applications.");
  } catch (error) {
    announce(error?.code === "declined" ? "Download cancelled." : "Couldn’t download Macscapes. Please try again.");
  } finally {
    downloadButtons.forEach(button => { button.disabled = false; });
  }
}
downloadButtons.forEach(button => button.addEventListener("click", downloadApp));
