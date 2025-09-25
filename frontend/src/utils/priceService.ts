/**
 * CoinGecko price fetching service for token prices
 */

// CoinGecko API endpoint for getting multiple token prices
const COINGECKO_API_BASE = 'https://api.coingecko.com/api/v3';

// Mapping of token symbols to CoinGecko IDs
const TOKEN_TO_COINGECKO_ID: Record<string, string> = {
  'USDC': 'usd-coin',
  'WETH': 'ethereum',
  'ETH': 'ethereum', // WETH and ETH have the same price
  'WBTC': 'bitcoin',
  'cbETH': 'coinbase-wrapped-staked-eth',
  'cbBTC': 'coinbase-wrapped-btc',
  'WSTETH': 'wrapped-steth',
  'AERO': 'aerodrome-finance',
  'COMP': 'compound-governance-token',
  // Compound tokens use their underlying asset prices
  'cUSDCv3': 'usd-coin',
  'cWETHv3': 'ethereum',
  'cAEROv3': 'aerodrome-finance',
};

// Cache for prices to avoid excessive API calls
interface PriceCache {
  prices: Record<string, number>;
  timestamp: number;
  expiresIn: number; // in milliseconds
}

let priceCache: PriceCache | null = null;
const CACHE_DURATION = 60 * 1000; // 1 minute

/**
 * Get prices for multiple tokens from CoinGecko
 */
export async function getTokenPrices(symbols: string[]): Promise<Record<string, number>> {
  // Check cache first
  if (priceCache && Date.now() - priceCache.timestamp < priceCache.expiresIn) {
    const cachedPrices: Record<string, number> = {};
    let allFound = true;
    
    for (const symbol of symbols) {
      if (priceCache.prices[symbol] !== undefined) {
        cachedPrices[symbol] = priceCache.prices[symbol];
      } else {
        allFound = false;
        break;
      }
    }
    
    if (allFound) {
      return cachedPrices;
    }
  }

  try {
    // Map symbols to CoinGecko IDs
    const coingeckoIds = symbols
      .map(symbol => TOKEN_TO_COINGECKO_ID[symbol])
      .filter(id => id !== undefined);

    if (coingeckoIds.length === 0) {
      throw new Error('No valid CoinGecko IDs found for the provided symbols');
    }

    // Remove duplicates
    const uniqueIds = [...new Set(coingeckoIds)];

    // Fetch prices from CoinGecko
    const response = await fetch(
      `${COINGECKO_API_BASE}/simple/price?ids=${uniqueIds.join(',')}&vs_currencies=usd&include_24hr_change=false`
    );

    if (!response.ok) {
      throw new Error(`CoinGecko API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();

    // Map the response back to our symbol format
    const prices: Record<string, number> = {};
    symbols.forEach(symbol => {
      const coingeckoId = TOKEN_TO_COINGECKO_ID[symbol];
      if (coingeckoId && data[coingeckoId]?.usd !== undefined) {
        prices[symbol] = data[coingeckoId].usd;
      }
    });

    // Update cache
    priceCache = {
      prices: { ...priceCache?.prices, ...prices },
      timestamp: Date.now(),
      expiresIn: CACHE_DURATION,
    };

    return prices;
  } catch (error) {
    console.error('Error fetching prices from CoinGecko:', error);
    
    // Return cached prices if available, otherwise return empty object
    if (priceCache && priceCache.prices) {
      const fallbackPrices: Record<string, number> = {};
      symbols.forEach(symbol => {
        if (priceCache!.prices[symbol] !== undefined) {
          fallbackPrices[symbol] = priceCache!.prices[symbol];
        }
      });
      return fallbackPrices;
    }
    
    return {};
  }
}

/**
 * Get price for a single token
 */
export async function getTokenPrice(symbol: string): Promise<number | null> {
  try {
    const prices = await getTokenPrices([symbol]);
    return prices[symbol] || null;
  } catch (error) {
    console.error(`Error fetching price for ${symbol}:`, error);
    return null;
  }
}

/**
 * Fallback prices in case CoinGecko is unavailable
 * These should be updated regularly or removed in production
 */
export const FALLBACK_PRICES: Record<string, number> = {
  'USDC': 1.00,
  'WETH': 3500.00,
  'ETH': 3500.00,
  'cbETH': 3450.00,
  'cbBTC': 95000.00,
  'WSTETH': 4100.00,
  'AERO': 1.50,
  'COMP': 85.00,
  'cUSDCv3': 1.00, // Uses USDC price
  'cWETHv3': 3500.00, // Uses ETH price
  'cAEROv3': 1.50, // Uses AERO price
};

/**
 * Get token price with fallback
 */
export async function getTokenPriceWithFallback(symbol: string): Promise<number> {
  const price = await getTokenPrice(symbol);
  return price !== null ? price : (FALLBACK_PRICES[symbol] || 0);
}

/**
 * Get multiple token prices with fallback
 */
export async function getTokenPricesWithFallback(symbols: string[]): Promise<Record<string, number>> {
  const prices = await getTokenPrices(symbols);
  
  // Fill in missing prices with fallbacks
  const result: Record<string, number> = {};
  symbols.forEach(symbol => {
    result[symbol] = prices[symbol] !== undefined ? prices[symbol] : (FALLBACK_PRICES[symbol] || 0);
  });
  
  return result;
}
