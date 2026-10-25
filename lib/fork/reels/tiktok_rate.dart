/// Скорость ×2 у роликов TikTok в ленте вдвоём (BACKLOG D1).
///
/// У встраиваемого плеера TikTok команды скорости нет, а кадр чужой — страница
/// ленты до его `<video>` не дотянется. Поэтому приложение кладёт этот скрипт
/// во все кадры `www.tiktok.com`: он слушает `{'x-fork-rate': 1|2}` только от
/// своей страницы ленты (`https://<siteHost>`) и ставит скорость всем роликам
/// кадра, в том числе тем, что появятся позже.
library;

import 'dart:convert';

String forkTikTokRateScript(String siteHost) {
  final origin = jsonEncode('https://$siteHost');
  return '(function(){'
      "if(location.hostname!=='www.tiktok.com'||window.top===window)return;"
      'var ok=$origin,rate=1;'
      "function all(){var v=document.getElementsByTagName('video');"
      'for(var i=0;i<v.length;i++){if(v[i].playbackRate!==rate)v[i].playbackRate=rate;}}'
      "window.addEventListener('message',function(e){"
      'if(e.origin!==ok||!e.data||typeof e.data!=="object")return;'
      "var r=Number(e.data['x-fork-rate']);if(r!==1&&r!==2)return;rate=r;all();});"
      // Новый ролик в кадре и чужая смена скорости — обратно к выбранной.
      "['play','loadedmetadata','ratechange'].forEach(function(t){"
      'document.addEventListener(t,function(e){var v=e.target;'
      "if(v&&v.tagName==='VIDEO'&&v.playbackRate!==rate)v.playbackRate=rate;},true);});"
      '})();';
}
