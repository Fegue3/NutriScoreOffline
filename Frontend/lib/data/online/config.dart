// Centraliza parâmetros da integração OFF.
// Ajusta aqui e tudo o resto respeita.

const kOffBaseUrl = 'https://world.openfoodfacts.org';
const kUserAgent = 'NutriScore/1.0 (contact: teu_email@exemplo.com)';

// Limites oficiais OFF
// - 100 req/min para produto individual
// - 10 req/min para pesquisas
// - 2 req/min para facets (evitamos por agora)
const kRateProductPerMinute = 100;
const kRateSearchPerMinute = 10;

// Concurrency global de chamadas HTTP ao domínio OFF
const kMaxConcurrentRequests = 2;

// Cache
const kCacheTtlDays = 7;
const kSearchPageSize = 30;

// Campos reduzidos para pesquisa (poupa banda)
const kSearchFields =
    'code,product_name,brands,nutriscore_grade,nutriments,image_small_url';
