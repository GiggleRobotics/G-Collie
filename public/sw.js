// No API/history cache: private conversations and pairing credentials stay off the offline cache.
self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('push',e=>{let d;try{d=e.data.json()}catch{d={body:'你有一条新的任务提醒'}}const url=typeof d.url==='string'&&d.url.startsWith('/?session=')?d.url:'/';e.waitUntil(self.registration.showNotification('G-Collie',{body:d.body||'任务状态发生变化',icon:'/brand/collie-mark-v2.png',badge:'/brand/collie-mark-v2.png',tag:d.tag||'task',data:{url}}))});
self.addEventListener('notificationclick',e=>{e.notification.close();e.waitUntil(self.clients.openWindow(e.notification.data?.url||'/'))});
