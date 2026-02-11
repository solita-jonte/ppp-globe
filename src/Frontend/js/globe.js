  import Globe from 'https://unpkg.com/three-globe@latest?module';
  import * as THREE from 'https://unpkg.com/three@0.162.0/build/three.module.js';

  // 1) Set up renderer/scene/camera
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(window.innerWidth, window.innerHeight);
  document.getElementById('globe').appendChild(renderer.domElement);

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
  const globe = new Globe()
    .globeImageUrl('//unpkg.com/three-globe/example/img/earth-blue-marble.jpg')
    .bumpImageUrl('//unpkg.com/three-globe/example/img/earth-topology.png');

  scene.add(globe);

  // Basic ambient + directional light
  const ambientLight = new THREE.AmbientLight(0xbbbbbb);
  scene.add(ambientLight);
  const dirLight = new THREE.DirectionalLight(0xffffff, 0.6);
  dirLight.position.set(-100, 50, 100);
  scene.add(dirLight);

  // 3) Animate (slow rotation)
  (function animate() {
    requestAnimationFrame(animate);
    globe.rotation.y += 0.0008;
    renderer.render(scene, camera);
  })();

  // Example color mapping: ISO-2 -> color
  const countryColors = {
    FI: '#1f77b4',
    SE: '#ff7f0e',
    NO: '#2ca02c',
    DE: '#d62728',
    // Default for all others handled below
  };

  // 4) Load country polygons GeoJSON
  // Use your own hosted file or a static URL
  fetch('https://your-static-site/countries.geojson')
    .then(res => res.json())
    .then(geojson => {
      // Ensure polygons have an ISO-2 property, e.g. ISO_A2
      const features = geojson.features.map(f => ({
        ...f,
        properties: {
          ...f.properties,
          iso2: (f.properties.ISO_A2 || f.properties.iso_a2 || '').toUpperCase()
        }
      }));

      globe
        .polygonsData(features)
        .polygonCapColor(feat => {
          const code = feat.properties.iso2;
          return countryColors[code] || 'rgba(100, 100, 100, 0.6)'; // fallback color
        })
        .polygonSideColor(() => 'rgba(0, 0, 0, 0.2)')      // side color (3D wall)
        .polygonStrokeColor(() => '#111111')               // outline color
        .polygonAltitude(0.003);                            // slight extrusion
    });
