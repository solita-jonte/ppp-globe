import * as THREE from 'three';
import ThreeGlobe from 'three-globe';

// Types for PPP API data
interface YearValue {
  year: number;
  value: number;
}

interface CountryValuesDto {
  iso3: string;
  name: string;
  values: YearValue[];
}

// 0) Read API base URL from environment (build-time)
const apiBaseUrl = import.meta.env.VITE_API_BASE_URL;

// 1) Set up renderer/scene/camera
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);

const container = document.getElementById('globe');
if (!container) {
  throw new Error('Missing #globe container element');
}
container.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(
  60,
  window.innerWidth / window.innerHeight,
  0.1,
  1000
);
camera.position.z = 250;

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// 2) Create globe
const globe = new (ThreeGlobe as any)()
  .globeImageUrl('//unpkg.com/three-globe/example/img/earth-blue-marble.jpg')
  .bumpImageUrl('//unpkg.com/three-globe/example/img/earth-topology.png');

scene.add(globe);

// Basic ambient + directional light
const ambientLight = new THREE.AmbientLight(0xbbbbbb);
scene.add(ambientLight);
const dirLight = new THREE.DirectionalLight(0xffffff, 0.6);
dirLight.position.set(-100, 50, 100);
scene.add(dirLight);

// 2b) Tooltip for hover / click info
const tooltip = document.createElement('div');
tooltip.className = 'globe-tooltip';
tooltip.style.display = 'none';
document.body.appendChild(tooltip);

// Track last mouse position so we can position tooltip
let lastMouseX = 0;
let lastMouseY = 0;

// Raycaster + mouse for custom polygon picking
const raycaster = new THREE.Raycaster();
const mouse = new THREE.Vector2();

// Auto‑rotation flag (also controlled by play/pause)
let autoRotateSpeed = 0.0008;
let autoRotateEnabled = true;

// 4) Year slider animation state
const yearSlider = document.getElementById('year-slider') as HTMLInputElement | null;
const yearLabel = document.getElementById('year-label');
const playPauseButton = document.getElementById('play-pause-button') as HTMLButtonElement | null;

if (!yearSlider || !yearLabel || !playPauseButton) {
  throw new Error('Missing year slider, label, or play/pause button elements');
}

const YEAR_MIN = parseInt(yearSlider.min, 10);
const YEAR_MAX = parseInt(yearSlider.max, 10);
let currentYear = YEAR_MIN;
let yearAnimationTimer: number | null = null;
let isYearDragging = false;
let isPlaying = true; // initial state: playing

// Update label + trigger recolor
function setYear(year: number): void {
  currentYear = year;
  yearSlider.value = String(year);
  yearLabel.textContent = String(year);
  updateGlobeColorsForYear(year);
}

// Simple animation: step year every N ms, loop at end
function startYearAnimation(): void {
  if (yearAnimationTimer !== null) return;
  yearAnimationTimer = window.setInterval(() => {
    if (isYearDragging) return; // safety, though we stop timer on drag
    let next = currentYear + 1;
    if (next > YEAR_MAX) {
      next = YEAR_MIN;
    }
    setYear(next);
  }, 1000); // 1 second per year; adjust as desired
}

function stopYearAnimation(): void {
  if (yearAnimationTimer !== null) {
    window.clearInterval(yearAnimationTimer);
    yearAnimationTimer = null;
  }
}

// Play/pause toggle: controls both year animation and globe rotation
function updatePlayPauseUi(): void {
  if (isPlaying) {
    playPauseButton.textContent = '❚❚';
    playPauseButton.setAttribute('aria-label', 'Pause animation');
  } else {
    playPauseButton.textContent = '▶';
    playPauseButton.setAttribute('aria-label', 'Play animation');
  }
}

function applyPlayPauseState(): void {
  if (isPlaying) {
    autoRotateEnabled = true;
    startYearAnimation();
  } else {
    autoRotateEnabled = false;
    stopYearAnimation();
  }
  updatePlayPauseUi();
}

playPauseButton.addEventListener('click', () => {
  isPlaying = !isPlaying;
  applyPlayPauseState();
});

// Slider events
yearSlider.addEventListener('input', e => {
  const target = e.target as HTMLInputElement;
  const year = parseInt(target.value, 10);
  setYear(year);
});

yearSlider.addEventListener('mousedown', () => {
  isYearDragging = true;
  stopYearAnimation();
});

yearSlider.addEventListener('mouseup', () => {
  isYearDragging = false;
  if (isPlaying) {
    startYearAnimation();
  }
});

// Touch support for mobile
yearSlider.addEventListener(
  'touchstart',
  () => {
    isYearDragging = true;
    stopYearAnimation();
  },
  { passive: true }
);

yearSlider.addEventListener(
  'touchend',
  () => {
    isYearDragging = false;
    if (isPlaying) {
      startYearAnimation();
    }
  },
  { passive: true }
);

// 3) OrbitControls for built‑in drag/zoom/pan
// We import OrbitControls from three/examples via module import
// (Vite will handle this correctly)
import('three/examples/jsm/controls/OrbitControls.js')
  .then(mod => {
    const OrbitControls = mod.OrbitControls;

    const controls = new OrbitControls(camera, renderer.domElement);

    // We want to orbit around the globe centre
    controls.target.set(0, 0, 0);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;

    // Disable built‑in autoRotate; we keep our own simple globe rotation
    controls.autoRotate = false;

    // When user starts interacting, pause auto‑rotation (but keep play/pause state)
    controls.addEventListener('start', () => {
      autoRotateEnabled = false;
    });

    // When user stops interacting, resume auto‑rotation only if playing
    controls.addEventListener('end', () => {
      autoRotateEnabled = isPlaying;
    });

    // Start year animation + set initial UI once controls are ready
    setYear(YEAR_MIN);
    applyPlayPauseState();

    // 6) Animate (slow rotation, paused while user is dragging/orbiting)
    (function animate() {
      requestAnimationFrame(animate);

      if (autoRotateEnabled) {
        globe.rotation.y += autoRotateSpeed;
      }

      controls.update();

      // Update hover each frame so tooltip follows rotating globe
      updateHoverFromLastMousePosition();

      renderer.render(scene, camera);
    })();
  })
  .catch(err => {
    console.error('Failed to load OrbitControls, falling back to simple rotation.', err);

    setYear(YEAR_MIN);
    applyPlayPauseState();

    (function animate() {
      requestAnimationFrame(animate);

      if (autoRotateEnabled) {
        globe.rotation.y += autoRotateSpeed;
      }

      // Update hover each frame so tooltip follows rotating globe
      updateHoverFromLastMousePosition();

      renderer.render(scene, camera);
    })();
  });

// 7) Country PPP data from backend
const countryPppUrl = `${apiBaseUrl}/country-ppp`;

// Map: ISO-3 -> { [year: number]: value }
let countryYearValues: Record<string, Record<number, number>> = Object.create(null);

// 8) Load PPP data from backend
async function loadCountryPppData(): Promise<void> {
  try {
    const res = await fetch(countryPppUrl);
    if (!res.ok) {
      throw new Error(`Failed to fetch PPP data: ${res.status} ${res.statusText}`);
    }
    const json = (await res.json()) as CountryValuesDto[] | any[];

    const map: Record<string, Record<number, number>> = Object.create(null);

    json.forEach((country: any) => {
      const iso3 = (country.Iso3 || country.iso3 || '').toUpperCase();
      if (!iso3) return;

      const yearMap: Record<number, number> = Object.create(null);
      (country.Values || country.values || []).forEach((v: any) => {
        const year = v.Year ?? v.year;
        const value = v.Value ?? v.value;
        if (typeof year === 'number' && value != null) {
          yearMap[year] = value;
        }
      });

      map[iso3] = yearMap;
    });

    countryYearValues = map;
    console.log(
      'Loaded PPP data for countries (ISO3):',
      Object.keys(countryYearValues).length
    );
  } catch (err) {
    console.error('Error loading PPP data from API:', err);
  }
}

// 9) Helper: interpolate between red and yellow and dark green based on a 0-1 value
// t = 0   -> red        (255, 0,   0)
// t = 0.5 -> yellow     (255, 255, 0)
// t = 1   -> dark green (0,   128, 0)
function interpolateRedYellowDarkGreen(t: number): string {
  const clamped = Math.max(0, Math.min(1, t));

  let r: number;
  let g: number;
  const b = 0;

  if (clamped <= 0.5) {
    // Red -> Yellow
    const localT = clamped / 0.5; // 0..1
    r = 255;
    g = Math.round(255 * localT);
  } else {
    // Yellow -> Dark Green
    const localT = (clamped - 0.5) / 0.5; // 0..1
    r = Math.round(255 * (1 - localT)); // 255 -> 0
    g = Math.round(255 - (255 - 128) * localT); // 255 -> 128
  }

  return `rgb(${r}, ${g}, ${b})`;
}

// 10) Helper: compute color and altitude for a country based on its rank for a given year
// We'll build a map of iso3 -> { color, altitude, normalizedValue }
let yearColorCache: Record<
  number,
  Record<string, { color: string; altitude: number; normalizedValue: number }>
> = Object.create(null);

function computeColorMapForYear(year: number) {
  // Check cache
  if (yearColorCache[year]) {
    return yearColorCache[year];
  }

  // Collect all countries with data for this year
  const entries: { iso3: string; value: number }[] = [];
  for (const iso3 in countryYearValues) {
    const yearMap = countryYearValues[iso3];
    const value = yearMap[year];
    if (value != null && value > 0) {
      entries.push({ iso3, value });
    }
  }

  if (entries.length === 0) {
    yearColorCache[year] = Object.create(null);
    return yearColorCache[year];
  }

  // Sort by value ascending
  entries.sort((a, b) => a.value - b.value);

  // Compute log values
  const logValues = entries.map(e => Math.log(e.value));
  const minLog = logValues[0];
  const maxLog = logValues[logValues.length - 1];
  const logRange = maxLog - minLog || 1;

  // Build map: iso3 -> { color, altitude, normalizedValue }
  const dataMap: Record<
    string,
    { color: string; altitude: number; normalizedValue: number }
  > = Object.create(null);

  entries.forEach((entry, index) => {
    const logVal = logValues[index];
    const t = (logVal - minLog) / logRange; // 0 to 1

    // Altitude range
    const minAltitude = 0.003;
    const maxAltitude = 0.03;
    const altitude = minAltitude + t * (maxAltitude - minAltitude);

    dataMap[entry.iso3] = {
      color: interpolateRedYellowDarkGreen(t),
      altitude,
      normalizedValue: t
    };
  });

  yearColorCache[year] = dataMap;
  return dataMap;
}

// 11) Load country polygons GeoJSON and set up globe polygons
let globeFeatures: any[] | null = null;

async function initGlobe(): Promise<void> {
  try {
    const res = await fetch('countries.geojson');
    const geojson = await res.json();

    globeFeatures = geojson.features.map((f: any) => ({
      ...f,
      properties: {
        ...f.properties,
        iso3: (f.id || f.properties.ISO_A3 || f.properties.iso_a3 || '').toUpperCase(),
        countryName: f.properties.ADMIN || f.properties.name || f.properties.NAME || ''
      }
    }));

    (globe as any)
      .polygonsData(globeFeatures)
      .polygonSideColor(() => 'rgba(0, 0, 0, 0.2)') // side color (3D wall)
      .polygonStrokeColor(() => '#111111'); // outline color

    // Load PPP data after we have the features
    await loadCountryPppData();

    // Initial color application for the starting year
    updateGlobeColorsForYear(currentYear);
  } catch (err) {
    console.error('Failed to initialise globe polygons or PPP data', err);
  }
}

initGlobe();

// 12) Recolor globe polygons for a given year using PPP data
function updateGlobeColorsForYear(year: number): void {
  if (!globeFeatures) return;

  const dataMap = computeColorMapForYear(year);

  (globe as any).polygonCapColor((feat: any) => {
    const iso3 = feat.properties.iso3 as string | undefined;
    if (!iso3) {
      return 'rgba(100, 100, 100, 0.6)';
    }

    const data = dataMap[iso3];
    if (data) {
      return data.color;
    }

    // No data for this country in this year
    return 'rgba(100, 100, 100, 0.6)';
  });

  (globe as any).polygonAltitude((feat: any) => {
    const iso3 = feat.properties.iso3 as string | undefined;
    if (!iso3) {
      return 0.003;
    }

    const data = dataMap[iso3];
    if (data) {
      return data.altitude;
    }

    // No data for this country in this year
    return 0.003;
  });
}

// 13) Hover interaction using our own raycaster

function updateTooltipForFeature(feat: any | null, clientX: number, clientY: number): void {
  if (!feat || !feat.data || !feat.data.properties) {
    tooltip.style.display = 'none';
    return;
  }

  const iso3: string = feat.data.properties.iso3;
  const countryName: string = feat.data.properties.countryName;

  let valueText = 'No data';
  if (iso3 && countryYearValues[iso3]) {
    const val = countryYearValues[iso3][currentYear];
    if (val != null) {
      const formatted = new Intl.NumberFormat('en-US', {
        maximumFractionDigits: 0
      }).format(val);
      valueText = `$${formatted}`;
    }
  }

  // Multi-line tooltip: country, year, value on separate lines using <br/>
  tooltip.innerHTML = `${countryName}<br/>${currentYear}<br/>${valueText}`;
  tooltip.style.display = 'block';

  // Position tooltip near mouse, keeping it in viewport
  const padding = 10;
  let x = clientX + 12;
  let y = clientY + 12;

  const rect = tooltip.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  if (x + rect.width + padding > vw) {
    x = clientX - rect.width - 12;
  }
  if (y + rect.height + padding > vh) {
    y = clientY - rect.height - 12;
  }

  tooltip.style.left = `${x}px`;
  tooltip.style.top = `${y}px`;
}

/**
 * Find the first intersected polygon feature using the internal meshes
 * created by three-globe. This replaces onPolygonHover/onPolygonClick.
 */
function getPolygonIntersectionFromRaycaster(
  clientX: number,
  clientY: number
): any | null {
  const rect = renderer.domElement.getBoundingClientRect();

  // Normalised device coordinates (-1 to +1)
  mouse.x = ((clientX - rect.left) / rect.width) * 2 - 1;
  mouse.y = -((clientY - rect.top) / rect.height) * 2 + 1;

  raycaster.setFromCamera(mouse, camera);

  // Intersect with all children of the globe (polygon meshes / line segments)
  const intersects = raycaster.intersectObjects(globe.children, true);

  if (!intersects.length) {
    return null;
  }

  // three-globe attaches the feature on the mesh as __data (UMD/ESM builds)
  for (const hit of intersects) {
    let obj: any = hit.object;
    while (obj) {
      if (obj.__data) {
        return obj.__data;
      }
      obj = obj.parent;
    }
  }

  return null;
}

/**
 * Called every frame from the animation loop to keep hover in sync
 * with the current globe rotation and camera position.
 */
function updateHoverFromLastMousePosition(): void {
  // If mouse has never entered the canvas, skip
  if (lastMouseX === 0 && lastMouseY === 0) {
    return;
  }

  const feat = getPolygonIntersectionFromRaycaster(lastMouseX, lastMouseY);
  if (!feat) {
    tooltip.style.display = 'none';
    return;
  }

  updateTooltipForFeature(feat, lastMouseX, lastMouseY);
}

// Track mouse position only; actual hover logic runs every frame
renderer.domElement.addEventListener('mousemove', event => {
  lastMouseX = event.clientX;
  lastMouseY = event.clientY;
});

// Hide tooltip when mouse leaves canvas
renderer.domElement.addEventListener('mouseleave', () => {
  tooltip.style.display = 'none';
  lastMouseX = 0;
  lastMouseY = 0;
}
);
