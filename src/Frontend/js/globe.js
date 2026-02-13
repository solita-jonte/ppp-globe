/* global THREE, ThreeGlobe, window */

// 0) Read API base URL from config.js (generated from config.template.js)
const apiBaseUrl =
  (window.APP_CONFIG && window.APP_CONFIG.apiBaseUrl) ||
  'http://127.0.0.1:7071/api';

// 1) Set up renderer/scene/camera
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
const container = document.getElementById('globe');
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
const globe = new ThreeGlobe()
  .globeImageUrl('//unpkg.com/three-globe/example/img/earth-blue-marble.jpg')
  .bumpImageUrl('//unpkg.com/three-globe/example/img/earth-topology.png');

scene.add(globe);

// Basic ambient + directional light
const ambientLight = new THREE.AmbientLight(0xbbbbbb);
scene.add(ambientLight);
const dirLight = new THREE.DirectionalLight(0xffffff, 0.6);
dirLight.position.set(-100, 50, 100);
scene.add(dirLight);

// 3) OrbitControls for built‑in drag/zoom/pan
// Load OrbitControls from the same three version as in index.html
const controlsScript = document.createElement('script');
controlsScript.src = 'https://unpkg.com/three@0.132.2/examples/js/controls/OrbitControls.js';
document.head.appendChild(controlsScript);

// Auto‑rotation flag
let autoRotateSpeed = 0.0008;
let autoRotateEnabled = true;

// 4) Year slider animation state
const yearSlider = document.getElementById('year-slider');
const yearLabel = document.getElementById('year-label');

const YEAR_MIN = parseInt(yearSlider.min, 10);
const YEAR_MAX = parseInt(yearSlider.max, 10);
let currentYear = YEAR_MIN;
let yearAnimationTimer = null;
let isYearDragging = false;

// Update label + trigger recolor
function setYear(year) {
  currentYear = year;
  yearSlider.value = String(year);
  yearLabel.textContent = String(year);
  updateGlobeColorsForYear(year);
}

// Simple animation: step year every N ms, loop at end
function startYearAnimation() {
  if (yearAnimationTimer) return;
  yearAnimationTimer = setInterval(() => {
    if (isYearDragging) return; // safety, though we stop timer on drag
    let next = currentYear + 1;
    if (next > YEAR_MAX) {
      next = YEAR_MIN;
    }
    setYear(next);
  }, 1000); // 1 second per year; adjust as desired
}

function stopYearAnimation() {
  if (yearAnimationTimer) {
    clearInterval(yearAnimationTimer);
    yearAnimationTimer = null;
  }
}

// Slider events
yearSlider.addEventListener('input', e => {
  const year = parseInt(e.target.value, 10);
  setYear(year);
});

yearSlider.addEventListener('mousedown', () => {
  isYearDragging = true;
  stopYearAnimation();
});

yearSlider.addEventListener('mouseup', () => {
  isYearDragging = false;
  startYearAnimation();
});

// Touch support for mobile
yearSlider.addEventListener('touchstart', () => {
    isYearDragging = true;
    stopYearAnimation();
}, { passive: true });

yearSlider.addEventListener('touchend', () => {
    isYearDragging = false;
    startYearAnimation();
}, { passive: true });

// 5) When OrbitControls script is loaded, set up controls and animation loop
controlsScript.onload = () => {
  // THREE.OrbitControls is attached to the THREE namespace by the script above
  const controls = new THREE.OrbitControls(camera, renderer.domElement);

  // We want to orbit around the globe centre
  controls.target.set(0, 0, 0);
  controls.enableDamping = true;
  controls.dampingFactor = 0.05;

  // Disable built‑in autoRotate; we keep our own simple globe rotation
  controls.autoRotate = false;

  // When user starts interacting, pause auto‑rotation
  controls.addEventListener('start', () => {
    autoRotateEnabled = false;
  });

  // When user stops interacting, resume auto‑rotation
  controls.addEventListener('end', () => {
    autoRotateEnabled = true;
  });

  // Start year animation once controls are ready
  setYear(YEAR_MIN);
  startYearAnimation();

  // 6) Animate (slow rotation, paused while user is dragging/orbiting)
  (function animate() {
    requestAnimationFrame(animate);

    if (autoRotateEnabled) {
      globe.rotation.y += autoRotateSpeed;
    }

    controls.update();
    renderer.render(scene, camera);
  })();
};

// Fallback animation loop in case OrbitControls fails to load
controlsScript.onerror = () => {
  console.error('Failed to load OrbitControls.js, falling back to simple rotation.');

  setYear(YEAR_MIN);
  startYearAnimation();

  (function animate() {
    requestAnimationFrame(animate);
    globe.rotation.y += autoRotateSpeed;
    renderer.render(scene, camera);
  })();
};

// 7) Country PPP data from backend
const countryPppUrl = `${apiBaseUrl}/country-ppp`;

// Map: ISO-3 -> { [year: number]: value }
let countryYearValues = Object.create(null);

// 8) Load PPP data from backend
function loadCountryPppData() {
  return fetch(countryPppUrl)
    .then(res => {
      if (!res.ok) {
        throw new Error(`Failed to fetch PPP data: ${res.status} ${res.statusText}`);
      }
      return res.json();
    })
    .then(json => {
      // Expected shape (per CountryValuesDto):
      // [
      //   {
      //     iso3: "SWE",
      //     name: "Sweden",
      //     values: [{ year: 2022, value: 63088.42 }, ...]
      //   },
      //   ...
      // ]
      const map = Object.create(null);

      json.forEach(country => {
        const iso3 = (country.Iso3 || country.iso3 || '').toUpperCase();
        if (!iso3) return;

        const yearMap = Object.create(null);
        (country.Values || country.values || []).forEach(v => {
          const year = v.Year ?? v.year;
          const value = v.Value ?? v.value;
          if (typeof year === 'number' && value != null) {
            yearMap[year] = value;
          }
        });

        map[iso3] = yearMap;
      });

      countryYearValues = map;
      console.log('Loaded PPP data for countries (ISO3):', Object.keys(countryYearValues).length);
    })
    .catch(err => {
      console.error('Error loading PPP data from API:', err);
    });
}

// 9) Example base color mapping: ISO-3 -> base color
// NOTE: The Holtzy world.geojson uses "id" with ISO-3 codes (e.g. "SWE", "FIN").
const baseCountryColors = {
  SWE: '#ff7f0e', // Sweden
  FIN: '#1f77b4', // Finland
  NOR: '#2ca02c', // Norway
  DEU: '#d62728'  // Germany
  // All others will use the fallback color below
};

// Helper: given a base color and a numeric value, return a color
// For now we just modulate lightness based on the value relative to a simple range.
function colorForValue(baseHex, value) {
  if (value == null || isNaN(value)) {
    return 'rgba(100, 100, 100, 0.6)'; // fallback for missing data
  }

  // Convert hex -> RGB
  const r = parseInt(baseHex.slice(1, 3), 16);
  const g = parseInt(baseHex.slice(3, 5), 16);
  const b = parseInt(baseHex.slice(5, 7), 16);

  // Clamp value into [0, 1] using a rough range (you can tune this)
  const minVal = 500;   // arbitrary low PPP
  const maxVal = 80000; // arbitrary high PPP
  const t = Math.max(0, Math.min(1, (value - minVal) / (maxVal - minVal || 1)));

  // Factor between 0.6 and 1.3 over the value range
  const factor = 0.6 + 0.7 * t;

  const nr = Math.max(0, Math.min(255, Math.round(r * factor)));
  const ng = Math.max(0, Math.min(255, Math.round(g * factor)));
  const nb = Math.max(0, Math.min(255, Math.round(b * factor)));

  return `rgb(${nr}, ${ng}, ${nb})`;
}

// 10) Load country polygons GeoJSON and set up globe polygons
let globeFeatures = null;

fetch('countries.geojson')
  .then(res => res.json())
  .then(geojson => {
    // Use ISO-3 code from the GeoJSON
    globeFeatures = geojson.features.map(f => ({
      ...f,
      properties: {
        ...f.properties,
        iso3: (f.id || f.properties.ISO_A3 || f.properties.iso_a3 || '').toUpperCase()
      }
    }));

    globe
      .polygonsData(globeFeatures)
      .polygonSideColor(() => 'rgba(0, 0, 0, 0.2)')      // side color (3D wall)
      .polygonStrokeColor(() => '#111111')               // outline color
      .polygonAltitude(0.003);                           // slight extrusion

    // Load PPP data after we have the features
    return loadCountryPppData();
  })
  .then(() => {
    // Initial color application for the starting year
    updateGlobeColorsForYear(currentYear);
  })
  .catch(err => {
    console.error('Failed to initialise globe polygons or PPP data', err);
  });

// 11) Recolor globe polygons for a given year using PPP data
function updateGlobeColorsForYear(year) {
  if (!globeFeatures) return;

  globe.polygonCapColor(feat => {
    const iso3 = feat.properties.iso3;
    if (!iso3) {
      return 'rgba(100, 100, 100, 0.6)';
    }

    const yearMap = countryYearValues[iso3];
    const value = yearMap ? yearMap[year] : null;

    const base = baseCountryColors[iso3] || '#646464'; // fallback base color
    return colorForValue(base, value);
  });
}
