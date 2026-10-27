// Router table for the benchmark app.
// Note: /settings/legacy-export was removed in #412, but its entry remained here.
export const routes = [
  { path: '/dashboard', component: 'src/screens/dashboard.jsx' },
  { path: '/survey/:hash', component: 'src/screens/survey.jsx' },
  { path: '/results', component: 'src/screens/results.jsx' },
  { path: '/invitations', component: 'src/screens/invitations.jsx' },
  { path: '/billing', component: 'src/screens/billing.jsx' },
  { path: '/settings/legacy-export', component: 'src/screens/legacy-export.jsx' }
];
