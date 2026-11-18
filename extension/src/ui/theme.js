// Kumo switches light/dark on data-mode; follow the system preference.
const media = matchMedia('(prefers-color-scheme: dark)');
const apply = () => { document.documentElement.dataset.mode = media.matches ? 'dark' : 'light'; };
apply();
media.addEventListener('change', apply);
