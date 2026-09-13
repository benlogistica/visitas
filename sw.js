/**
 * Service Worker do Nutricionais Visitas — versão 9.32.420
 *
 * Duas funções:
 *   1. Tornar o app instalável (critério de PWA do Chrome).
 *   2. Receber notificações push e mostrá-las na tela do celular,
 *      MESMO com o app fechado. É isto que resolve o problema do
 *      check-out esquecido: hoje o aviso existe, mas só aparece
 *      para quem abre o app — e quem esqueceu, por definição, não abriu.
 *
 * Sem cache offline ainda. O fetch passa direto.
 */

const CACHE_VERSION = 'v2';

self.addEventListener('install', () => {
  // Assume o controle já na primeira carga, sem esperar as abas antigas
  // fecharem. Sem isso, a versão nova do SW só valeria na visita seguinte.
  self.skipWaiting();
});

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

self.addEventListener('fetch', () => {
  // Pass-through — não intercepta nada.
});

/* ==========================================================================
   PUSH — chega mesmo com o app fechado
   ========================================================================== */

self.addEventListener('push', (event) => {
  let dados = {};
  try {
    dados = event.data ? event.data.json() : {};
  } catch (e) {
    // Se vier texto puro em vez de JSON, aproveita como corpo da mensagem.
    dados = { corpo: event.data ? event.data.text() : '' };
  }

  const titulo = dados.titulo || 'B&N Logística';
  const opcoes = {
    body: dados.corpo || '',
    icon: 'icons/icon-pwa.png?v=20260427',
    badge: 'icons/icon-pwa.png?v=20260427',
    lang: 'pt-BR',
    // tag agrupa: um novo aviso da MESMA visita substitui o anterior
    // em vez de empilhar três notificações sobre a mesma coisa.
    tag: dados.tag || 'bn-aviso',
    renotify: Boolean(dados.tag),
    requireInteraction: Boolean(dados.fixar),
    data: { url: dados.url || './', visitaId: dados.visitaId || null },
    vibrate: [120, 60, 120],
  };

  event.waitUntil(self.registration.showNotification(titulo, opcoes));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const destino = (event.notification.data && event.notification.data.url) || './';

  // Se o app já estiver aberto numa aba, foca nela em vez de abrir outra.
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((janelas) => {
        for (const j of janelas) {
          if ('focus' in j) {
            if ('navigate' in j && destino !== './') {
              return j.navigate(destino).then((c) => c && c.focus());
            }
            return j.focus();
          }
        }
        if (self.clients.openWindow) return self.clients.openWindow(destino);
      })
      .catch(() => {
        if (self.clients.openWindow) return self.clients.openWindow(destino);
      })
  );
});

/* O navegador pode trocar o endpoint do aparelho sozinho. Quando isso
   acontece, avisamos as abas abertas para regravarem a inscrição. */
self.addEventListener('pushsubscriptionchange', (event) => {
  event.waitUntil(
    self.clients.matchAll({ includeUncontrolled: true }).then((janelas) => {
      janelas.forEach((j) => j.postMessage({ tipo: 'push-reinscrever' }));
    })
  );
});
