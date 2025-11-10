// Centraliza parâmetros da integração OFF (OpenFoodFacts).
// Ajusta aqui e o resto do código respeita estes valores.

// -----------------------------------------------------------------------------
// Endpoints & Identidade HTTP
// -----------------------------------------------------------------------------

/// Base URL do Open Food Facts (produção).
const kOffBaseUrl = 'https://world.openfoodfacts.org';

/// User-Agent a usar em TODAS as chamadas ao OFF.
/// Substitui o contacto por um email real (para futura publicação da aplicação).
const kUserAgent = 'NutriScore/1.0 (contact: teu_email@exemplo.com)';

// -----------------------------------------------------------------------------
// Rate Limits oficiais OFF
// -----------------------------------------------------------------------------
// - Produto individual: até **100 req/min**
// - Pesquisas:          até **10 req/min**
// - Facets:             até **2 req/min** (evitamos por agora)
//
// Estes limites são respeitados pelo `NetThrottle` e pelos repositórios remotos.

/// Limite por minuto para pedidos de **produto individual** (`/api/v2/product/...`).
const kRateProductPerMinute = 100;

/// Limite por minuto para **pesquisas** (`/cgi/search.pl`).
const kRateSearchPerMinute = 10;

// -----------------------------------------------------------------------------
// Concorrência global
// -----------------------------------------------------------------------------
/// Número máximo de pedidos HTTP **em paralelo** ao domínio OFF.
/// Mantém baixo para ser “um bom cidadão” e reduzir *spikes*.
const kMaxConcurrentRequests = 2;

// -----------------------------------------------------------------------------
// Cache & Paginação
// -----------------------------------------------------------------------------
/// TTL (em dias) para cache local de produtos obtidos online.
/// Após este período, os produtos podem ser refrescados em *background*.
const kCacheTtlDays = 7;

/// Tamanho de página por omissão nas pesquisas ao OFF.
/// Mantém-se moderado para equilibrar latência e consumo de dados.
const kSearchPageSize = 30;

// -----------------------------------------------------------------------------
// Campos de pesquisa
// -----------------------------------------------------------------------------
/// Campos mínimos devolvidos nas pesquisas para **poupar largura de banda**.
/// - `code`               : barcode
/// - `product_name`       : nome do produto
/// - `brands`             : marca(s)
/// - `nutriscore_grade`   : letra A..E (se disponível)
/// - `nutriments`         : bloco com energia/macr os por 100 g
/// - `image_small_url`    : thumbnail leve para listagens
const kSearchFields =
    'code,product_name,brands,nutriscore_grade,nutriments,image_small_url';
