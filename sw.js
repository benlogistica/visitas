/**
 * Service Worker mínimo do Nutricionais Visitas.
 *
 * Este SW é OBRIGATÓRIO pra o Chrome considerar o app instalável (critério PWA).
 * Por enquanto não faz cache offline — só responde ao fetch passando direto.
 *
 * Numa futura iteração, pode ser estendido pra cache offline de assets estáticos.
 */

const CACHE_VERSION = 'v1';

// Ativação: limpa caches antigos (pra futuras versões)
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(
        names.filter((n) => n !== CACHE_VERSION).map((n) => caches.delete(n))
      )
    )
  );
  self.clients.claim();
});

// Fetch: sempre pega do network (sem cache offline ainda)
// O navegador continua usando cache HTTP padrão dos assets
self.addEventListener('fetch', () => {
  // Pass-through — não intercepta nada
});
