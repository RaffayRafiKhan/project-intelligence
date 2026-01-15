app/page.tsx
app/product/[slug]/page.tsx

app/api/search/route.ts ```typescript
import { NextRequest, NextResponse } from 'next/server';

interface SearchResult {
  title: string;
  url: string;
  description: string;
}

interface ProductSearchResponse {
  query: string;
  officialWebsite: SearchResult | null;
  retailers: SearchResult[];
  reviews: SearchResult[];
  rawData: {
    totalResults: number;
    searchEngine: string;
  };
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { query } = body;

    if (!query || typeof query !== 'string') {
      return NextResponse.json(
        { error: 'Invalid query parameter' },
        { status: 400 }
      );
    }

    const apiKey = process.env.BRAVE_SEARCH_API_KEY;

    if (!apiKey) {
      return NextResponse.json(
        { error: 'API key not configured' },
        { status: 500 }
      );
    }

    const searchUrl = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=20`;

    const response = await fetch(searchUrl, {
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
        'X-Subscription-Token': apiKey,
      },
    });

    if (!response.ok) {
      throw new Error(`Brave Search API error: ${response.status}`);
    }

    const data = await response.json();
    const results = data.web?.results || [];

    const officialWebsite = findOfficialWebsite(results, query);
    const retailers = findRetailers(results);
    const reviews = findReviews(results);

    const productData: ProductSearchResponse = {
      query,
      officialWebsite,
      retailers,
      reviews,
      rawData: {
        totalResults: results.length,
        searchEngine: 'Brave Search',
      },
    };

    return NextResponse.json(productData, { status: 200 });

  } catch (error) {
    console.error('Search API error:', error);
    return NextResponse.json(
      { 
        error: 'Failed to fetch search results',
        details: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    );
  }
}

function findOfficialWebsite(results: any[], query: string): SearchResult | null {
  const officialKeywords = ['official', 'official site', query.toLowerCase()];
  
  for (const result of results) {
    const title = result.title?.toLowerCase() || '';
    const url = result.url?.toLowerCase() || '';
    const description = result.description?.toLowerCase() || '';
    
    const isOfficial = 
      title.includes('official') ||
      description.includes('official site') ||
      url.includes(query.toLowerCase().replace(/\s+/g, ''));

    if (isOfficial) {
      return {
        title: result.title || '',
        url: result.url || '',
        description: result.description || '',
      };
    }
  }

  return results.length > 0 ? {
    title: results[0].title || '',
    url: results[0].url || '',
    description: results[0].description || '',
  } : null;
}

function findRetailers(results: any[]): SearchResult[] {
  const retailerDomains = [
    'amazon.com',
    'walmart.com',
    'target.com',
    'bestbuy.com',
    'ebay.com',
    'newegg.com',
    'alibaba.com',
    'aliexpress.com',
  ];

  return results
    .filter((result) => {
      const url = result.url?.toLowerCase() || '';
      return retailerDomains.some((domain) => url.includes(domain));
    })
    .map((result) => ({
      title: result.title || '',
      url: result.url || '',
      description: result.description || '',
    }))
    .slice(0, 5);
}

function findReviews(results: any[]): SearchResult[] {
  const reviewKeywords = ['review', 'reviews', 'rating', 'ratings', 'tested', 'hands-on'];
  const reviewDomains = [
    'reddit.com',
    'trustpilot.com',
    'consumerreports.org',
    'wirecutter.com',
    'cnet.com',
    'pcmag.com',
    'tomsguide.com',
    'techradar.com',
  ];

  return results
    .filter((result) => {
      const title = result.title?.toLowerCase() || '';
      const url = result.url?.toLowerCase() || '';
      const description = result.description?.toLowerCase() || '';
      
      const hasReviewKeyword = reviewKeywords.some(
        (keyword) => title.includes(keyword) || description.includes(keyword)
      );
      
      const isReviewSite = reviewDomains.some((domain) => url.includes(domain));

      return hasReviewKeyword || isReviewSite;
    })
    .map((result) => ({
      title: result.title || '',
      url: result.url || '',
      description: result.description || '',
    }))
    .slice(0, 5);
}
```
app/api/summarize/route.ts import { NextRequest, NextResponse } from 'next/server';
import { classifySeller, classifyMultipleSellers } from '@/lib/authenticity';

interface SearchResult {
  title: string;
  url: string;
  description: string;
}

interface ProductSearchData {
  query: string;
  officialWebsite: SearchResult | null;
  retailers: SearchResult[];
  reviews: SearchResult[];
  rawData: {
    totalResults: number;
    searchEngine: string;
  };
}

interface ProductSummary {
  name: string;
  category: string;
  description: string;
  keyFeatures: string[];
}

interface ProductScore {
  overall: number;
  authenticity: number;
  availability: number;
  reviewQuality: number;
  factors: {
    hasOfficialSource: boolean;
    authorizedRetailerCount: number;
    reviewSourceCount: number;
    marketplacePresence: boolean;
  };
}

interface ClassifiedSeller {
  url: string;
  title: string;
  description: string;
  classification: {
    type: 'official' | 'authorized' | 'marketplace' | 'unknown';
    confidence: 'high' | 'medium' | 'low';
    reason: string;
  };
}

interface SummarizeResponse {
  product: ProductSummary;
  score: ProductScore;
  sources: {
    official: ClassifiedSeller | null;
    authorizedRetailers: ClassifiedSeller[];
    marketplaceSellers: ClassifiedSeller[];
    reviews: SearchResult[];
  };
  metadata: {
    processedAt: string;
    totalSources: number;
    searchEngine: string;
  };
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const searchData: ProductSearchData = body;

    if (!searchData.query) {
      return NextResponse.json(
        { error: 'Invalid search data: missing query' },
        { status: 400 }
      );
    }

    const productSummary = summarizeProduct(searchData);
    const classifiedSellers = classifyAllSellers(searchData);
    const productScore = scoreProduct(searchData, classifiedSellers);

    const response: SummarizeResponse = {
      product: productSummary,
      score: productScore,
      sources: {
        official: classifiedSellers.official,
        authorizedRetailers: classifiedSellers.authorized,
        marketplaceSellers: classifiedSellers.marketplace,
        reviews: searchData.reviews,
      },
      metadata: {
        processedAt: new Date().toISOString(),
        totalSources: searchData.rawData.totalResults,
        searchEngine: searchData.rawData.searchEngine,
      },
    };

    return NextResponse.json(response, { status: 200 });

  } catch (error) {
    console.error('Summarize API error:', error);
    return NextResponse.json(
      {
        error: 'Failed to summarize product data',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

function summarizeProduct(data: ProductSearchData): ProductSummary {
  const query = data.query;
  const officialSite = data.officialWebsite;
  
  const description = officialSite?.description || 
    data.retailers[0]?.description || 
    `Product information for ${query}`;

  const keyFeatures = extractKeyFeatures(
    officialSite?.description || '',
    data.retailers.slice(0, 3).map(r => r.description).join(' ')
  );

  const category = inferCategory(query, description);

  return {
    name: query,
    category,
    description,
    keyFeatures,
  };
}

function extractKeyFeatures(officialDesc: string, retailerDescs: string): string[] {
  const combined = `${officialDesc} ${retailerDescs}`.toLowerCase();
  const features: string[] = [];

  const patterns = [
    /(\d+[a-z]{2,3})\s+(display|screen|monitor)/gi,
    /(\d+gb|\d+tb)\s+(ram|memory|storage|ssd|hdd)/gi,
    /(wireless|bluetooth|wifi|5g|4g)/gi,
    /(waterproof|water.resistant|ip\d+)/gi,
    /(battery|mah|\d+.hour)/gi,
  ];

  patterns.forEach(pattern => {
    const matches = combined.match(pattern);
    if (matches) {
      matches.slice(0, 2).forEach(match => {
        if (!features.includes(match)) {
          features.push(match);
        }
      });
    }
  });

  return features.slice(0, 5);
}

function inferCategory(query: string, description: string): string {
  const text = `${query} ${description}`.toLowerCase();

  const categories: Record<string, string[]> = {
    'Electronics': ['phone', 'laptop', 'tablet', 'computer', 'tv', 'monitor', 'camera'],
    'Fashion': ['shoes', 'clothing', 'dress', 'shirt', 'jacket', 'apparel', 'fashion'],
    'Home & Kitchen': ['furniture', 'appliance', 'kitchen', 'cookware', 'bedding'],
    'Beauty': ['makeup', 'skincare', 'cosmetic', 'beauty', 'perfume', 'fragrance'],
    'Sports': ['fitness', 'exercise', 'sport', 'athletic', 'gym', 'outdoor'],
    'Toys & Games': ['toy', 'game', 'puzzle', 'board game', 'video game'],
    'Books': ['book', 'novel', 'textbook', 'ebook', 'reading'],
    'Automotive': ['car', 'vehicle', 'automotive', 'motorcycle', 'bike'],
  };

  for (const [category, keywords] of Object.entries(categories)) {
    if (keywords.some(keyword => text.includes(keyword))) {
      return category;
    }
  }

  return 'General';
}

function classifyAllSellers(data: ProductSearchData): {
  official: ClassifiedSeller | null;
  authorized: ClassifiedSeller[];
  marketplace: ClassifiedSeller[];
  unknown: ClassifiedSeller[];
} {
  const allSources = [
    ...(data.officialWebsite ? [data.officialWebsite] : []),
    ...data.retailers,
  ];

  const classified = classifyMultipleSellers(
    allSources.map(s => ({
      url: s.url,
      title: s.title,
      description: s.description,
    })),
    data.query
  );

  const result: {
    official: ClassifiedSeller | null;
    authorized: ClassifiedSeller[];
    marketplace: ClassifiedSeller[];
    unknown: ClassifiedSeller[];
  } = {
    official: null,
    authorized: [],
    marketplace: [],
    unknown: [],
  };

  classified.forEach(item => {
    const source = allSources.find(s => s.url === item.url);
    if (!source) return;

    const classifiedSeller: ClassifiedSeller = {
      url: item.url,
      title: source.title,
      description: source.description,
      classification: item.classification,
    };

    if (item.classification.type === 'official' && !result.official) {
      result.official = classifiedSeller;
    } else if (item.classification.type === 'authorized') {
      result.authorized.push(classifiedSeller);
    } else if (item.classification.type === 'marketplace') {
      result.marketplace.push(classifiedSeller);
    } else {
      result.unknown.push(classifiedSeller);
    }
  });

  return result;
}

function scoreProduct(
  data: ProductSearchData,
  classified: {
    official: ClassifiedSeller | null;
    authorized: ClassifiedSeller[];
    marketplace: ClassifiedSeller[];
    unknown: ClassifiedSeller[];
  }
): ProductScore {
  const hasOfficialSource = classified.official !== null;
  const authorizedRetailerCount = classified.authorized.length;
  const reviewSourceCount = data.reviews.length;
  const marketplacePresence = classified.marketplace.length > 0;

  const authenticityScore = calculateAuthenticityScore(
    hasOfficialSource,
    authorizedRetailerCount,
    classified.authorized
  );

  const availabilityScore = calculateAvailabilityScore(
    authorizedRetailerCount,
    classified.marketplace.length
  );

  const reviewQualityScore = calculateReviewQualityScore(reviewSourceCount);

  const overallScore = Math.round(
    authenticityScore * 0.4 +
    availabilityScore * 0.3 +
    reviewQualityScore * 0.3
  );

  return {
    overall: overallScore,
    authenticity: authenticityScore,
    availability: availabilityScore,
    reviewQuality: reviewQualityScore,
    factors: {
      hasOfficialSource,
      authorizedRetailerCount,
      reviewSourceCount,
      marketplacePresence,
    },
  };
}

function calculateAuthenticityScore(
  hasOfficial: boolean,
  authorizedCount: number,
  authorizedSellers: ClassifiedSeller[]
): number {
  let score = 0;

  if (hasOfficial) {
    score += 50;
  }

  score += Math.min(authorizedCount * 10, 30);

  const highConfidenceCount = authorizedSellers.filter(
    s => s.classification.confidence === 'high'
  ).length;

  score += Math.min(highConfidenceCount * 5, 20);

  return Math.min(score, 100);
}

function calculateAvailabilityScore(
  authorizedCount: number,
  marketplaceCount: number
): number {
  let score = 0;

  score += Math.min(authorizedCount * 20, 60);
  score += Math.min(marketplaceCount * 10, 40);

  return Math.min(score, 100);
}

function calculateReviewQualityScore(reviewCount: number): number {
  if (reviewCount === 0) return 0;
  if (reviewCount >= 5) return 100;

  return reviewCount * 20;
}

lib/search.ts
lib/ai.ts import { ProductData, Review } from './types';

interface SummaryResult {
  pros: string[];
  cons: string[];
  sentimentSummary: string;
}

/**
 * Analyzes product data and reviews to generate a neutral summary
 * @param productData - Basic product information
 * @param reviews - Array of customer reviews
 * @returns Object containing pros, cons, and sentiment summary
 */
export function summarizeProduct(
  productData: ProductData,
  reviews: Review[]
): SummaryResult {
  // Extract key features from product data
  const features = extractKeyFeatures(productData);
  
  // Analyze review sentiment and feedback patterns
  const sentimentAnalysis = analyzeSentiment(reviews);
  
  // Identify common positive themes
  const pros = identifyPros(reviews, features);
  
  // Identify common negative themes
  const cons = identifyCons(reviews, features);
  
  // Generate neutral sentiment summary
  const sentimentSummary = generateSentimentSummary(sentimentAnalysis, pros, cons);
  
  return {
    pros,
    cons,
    sentimentSummary
  };
}

function extractKeyFeatures(productData: ProductData): string[] {
  const features: string[] = [];
  
  if (productData.specifications) {
    Object.entries(productData.specifications).forEach(([key, value]) => {
      if (typeof value === 'string' && value.length > 0) {
        features.push(`${key}: ${value}`);
      } else if (Array.isArray(value) && value.length > 0) {
        features.push(`${key}: ${value.join(', ')}`);
      }
    });
  }
  
  if (productData.description) {
    const sentences = productData.description.split(/[.!?]/).filter(s => s.trim().length > 10);
    if (sentences.length > 0) {
      features.push(...sentences.slice(0, 3).map(s => s.trim()));
    }
  }
  
  return features;
}

function analyzeSentiment(reviews: Review[]): {
  positiveCount: number;
  negativeCount: number;
  neutralCount: number;
  averageRating: number;
} {
  let positiveCount = 0;
  let negativeCount = 0;
  let neutralCount = 0;
  let totalRating = 0;
  let reviewCount = 0;
  
  reviews.forEach(review => {
    if (review.rating) {
      totalRating += review.rating;
      reviewCount++;
      
      if (review.rating >= 4) positiveCount++;
      else if (review.rating <= 2) negativeCount++;
      else neutralCount++;
    }
    
    // Fallback to text analysis if no rating provided
    if (review.text && !review.rating) {
      const positiveKeywords = ['excellent', 'great', 'good', 'love', 'recommend', 'perfect', 'happy'];
      const negativeKeywords = ['poor', 'bad', 'disappointing', 'hate', 'terrible', 'broken', 'waste'];
      
      const lowerText = review.text.toLowerCase();
      const positiveMatches = positiveKeywords.filter(word => lowerText.includes(word)).length;
      const negativeMatches = negativeKeywords.filter(word => lowerText.includes(word)).length;
      
      if (positiveMatches > negativeMatches) positiveCount++;
      else if (negativeMatches > positiveMatches) negativeCount++;
      else neutralCount++;
    }
  });
  
  return {
    positiveCount,
    negativeCount,
    neutralCount,
    averageRating: reviewCount > 0 ? totalRating / reviewCount : 0
  };
}

function identifyPros(reviews: Review[], features: string[]): string[] {
  const prosMap = new Map<string, number>();
  const positiveKeywords = [
    'durable', 'reliable', 'easy to use', 'quality', 'comfortable', 
    'fast', 'efficient', 'value', 'well made', 'effective'
  ];
  
  reviews.forEach(review => {
    if (review.rating && review.rating >= 4 && review.text) {
      const lowerText = review.text.toLowerCase();
      
      // Check for feature-specific praise
      features.forEach(feature => {
        const featureLower = feature.toLowerCase();
        if (lowerText.includes(featureLower) && 
            (lowerText.includes('good') || lowerText.includes('great') || 
             lowerText.includes('excellent') || lowerText.includes('love'))) {
          const key = featureLower.split(':')[0].trim();
          prosMap.set(key, (prosMap.get(key) || 0) + 1);
        }
      });
      
      // Check for general positive attributes
      positiveKeywords.forEach(keyword => {
        if (lowerText.includes(keyword)) {
          prosMap.set(keyword, (prosMap.get(keyword) || 0) + 1);
        }
      });
    }
  });
  
  // Sort by frequency and take top 5
  return Array.from(prosMap.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([pro]) => pro.charAt(0).toUpperCase() + pro.slice(1));
}

function identifyCons(reviews: Review[], features: string[]): string[] {
  const consMap = new Map<string, number>();
  const negativeKeywords = [
    'expensive', 'flimsy', 'uncomfortable', 'slow', 'inefficient',
    'difficult', 'poor quality', 'breaks', 'defective', 'overpriced'
  ];
  
  reviews.forEach(review => {
    if (review.rating && review.rating <= 2 && review.text) {
      const lowerText = review.text.toLowerCase();
      
      // Check for feature-specific complaints
      features.forEach(feature => {
        const featureLower = feature.toLowerCase();
        if (lowerText.includes(featureLower) && 
            (lowerText.includes('bad') || lowerText.includes('poor') || 
             lowerText.includes('disappointing') || lowerText.includes('hate'))) {
          const key = featureLower.split(':')[0].trim();
          consMap.set(key, (consMap.get(key) || 0) + 1);
        }
      });
      
      // Check for general negative attributes
      negativeKeywords.forEach(keyword => {
        if (lowerText.includes(keyword)) {
          consMap.set(keyword, (consMap.get(keyword) || 0) + 1);
        }
      });
    }
  });
  
  // Sort by frequency and take top 5
  return Array.from(consMap.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([con]) => con.charAt(0).toUpperCase() + con.slice(1));
}

function generateSentimentSummary(
  sentimentAnalysis: ReturnType<typeof analyzeSentiment>,
  pros: string[],
  cons: string[]
): string {
  const totalReviews = sentimentAnalysis.positiveCount + sentimentAnalysis.negativeCount + sentimentAnalysis.neutralCount;
  
  if (totalReviews === 0) {
    return 'No reviews available for analysis.';
  }
  
  const positivePercentage = Math.round((sentimentAnalysis.positiveCount / totalReviews) * 100);
  const negativePercentage = Math.round((sentimentAnalysis.negativeCount / totalReviews) * 100);
  
  let summary = `Based on ${totalReviews} reviews, `;
  
  if (positivePercentage >= 70) {
    summary += 'customers generally express satisfaction with this product. ';
  } else if (negativePercentage >= 70) {
    summary += 'customers generally express dissatisfaction with this product. ';
  } else {
    summary += 'customer opinions are mixed regarding this product. ';
  }
  
  if (pros.length > 0 && cons.length > 0) {
    summary += `Common positive feedback includes ${pros.slice(0, 2).join(' and ')}. `;
    summary += `Common concerns include ${cons.slice(0, 2).join(' and ')}.`;
  } else if (pros.length > 0) {
    summary += `Customers frequently praise ${pros.slice(0, 2).join(' and ')}.`;
  } else if (cons.length > 0) {
    summary += `Customers frequently mention issues with ${cons.slice(0, 2).join(' and ')}.`;
  }
  
  return summary.trim();
}
lib/scoring.ts export interface RawProductData {
  id: string;
  name: string;
  price: number;
  originalPrice?: number;
  discountPercentage?: number;
  brand: string;
  materials: string[];
  reviewCount: number;
  averageRating: number;
  reviewTexts?: string[];
  warrantyMonths?: number;
  returnRate?: number; // 0-1 percentage
  competitorPrices?: number[];
  category: string;
  specifications?: Record<string, string>;
}

export interface ProductScores {
  quality: number;
  durability: number;
  valueForMoney: number;
}

// Brand trust mapping (expandable)
const BRAND_TRUST_SCORES: Record<string, number> = {
  'apple': 9.0,
  'samsung': 8.5,
  'sony': 8.7,
  'bosch': 9.2,
  'whirlpool': 8.3,
  'dyson': 8.8,
  'lenovo': 7.8,
  'dell': 8.2,
  'lg': 8.4,
  'patagonia': 9.5,
  'stanley': 9.1,
  'yet': 8.9,
  'costco': 9.3,
  'ikea': 7.5,
  'generic': 5.0,
  'offbrand': 4.0,
};

// Material quality scores
const MATERIAL_SCORES: Record<string, number> = {
  'stainless steel': 9.0,
  'aluminum': 8.0,
  'carbon fiber': 9.5,
  'titanium': 9.8,
  'solid wood': 8.5,
  'hardwood': 8.2,
  'plywood': 6.5,
  'ceramic': 8.0,
  'glass': 7.5,
  'merino wool': 8.8,
  'cashmere': 9.0,
  'organic cotton': 7.8,
  'cotton': 6.5,
  'polyester': 5.0,
  'nylon': 6.0,
  'plastic': 4.0,
  'abs plastic': 5.5,
  'pvc': 4.5,
  'rubber': 6.0,
  'leather': 8.0,
  'genuine leather': 8.5,
  'full grain leather': 9.2,
};

// Durability indicators
const DURABILITY_KEYWORDS = [
  'waterproof', 'shockproof', 'dustproof', 'corrosion resistant',
  'scratch resistant', 'impact resistant', 'weather resistant',
  'heavy duty', 'industrial', 'commercial grade', 'military grade'
];

/**
 * Calculate product quality score (0-10)
 */
function calculateQualityScore(data: RawProductData): number {
  let score = 0;
  let factors = 0;

  // 1. Review sentiment (40% weight)
  if (data.averageRating > 0) {
    const ratingScore = (data.averageRating / 5) * 4; // Scale 0-4
    const reviewVolumeBonus = Math.min(data.reviewCount / 100, 1); // Cap at 1 point
    score += ratingScore + reviewVolumeBonus;
    factors += 5; // 4 for rating + 1 for volume
  }

  // 2. Brand trust (30% weight)
  const brandLower = data.brand.toLowerCase();
  const brandScore = BRAND_TRUST_SCORES[brandLower] || 6.0;
  score += (brandScore / 10) * 3;
  factors += 3;

  // 3. Material quality (20% weight)
  let materialScore = 0;
  if (data.materials.length > 0) {
    const scores = data.materials.map(material => 
      MATERIAL_SCORES[material.toLowerCase()] || 5.0
    );
    materialScore = Math.max(...scores); // Use best material
    score += (materialScore / 10) * 2;
    factors += 2;
  }

  // 4. Return rate penalty (10% weight)
  if (data.returnRate !== undefined) {
    const returnPenalty = Math.min(data.returnRate * 10, 1); // 10% return = -1 point
    score -= returnPenalty;
  }

  // Normalize to 0-10 scale
  return factors > 0 ? Math.min(Math.max((score / factors) * 10, 0), 10) : 5.0;
}

/**
 * Calculate product durability score (0-10)
 */
function calculateDurabilityScore(data: RawProductData): number {
  let score = 5.0; // Base score

  // 1. Warranty period (0-4 points)
  if (data.warrantyMonths) {
    const warrantyScore = Math.min(data.warrantyMonths / 12, 4); // 1 year = 1 point, max 4
    score += warrantyScore;
  }

  // 2. Material durability (0-3 points)
  if (data.materials.length > 0) {
    const materialScores = data.materials.map(material => 
      MATERIAL_SCORES[material.toLowerCase()] || 5.0
    );
    const avgMaterialScore = materialScores.reduce((a, b) => a + b) / materialScores.length;
    score += (avgMaterialScore / 10) * 3;
  }

  // 3. Specification keywords (0-2 points)
  const specs = data.specifications || {};
  const specText = Object.values(specs).join(' ').toLowerCase();
  const durabilityMatches = DURABILITY_KEYWORDS.filter(keyword => 
    specText.includes(keyword)
  ).length;
  score += Math.min(durabilityMatches * 0.5, 2); // 0.5 points per keyword

  // 4. Brand trust bonus (0-1 point)
  const brandLower = data.brand.toLowerCase();
  const brandTrust = BRAND_TRUST_SCORES[brandLower] || 5.0;
  score += (brandTrust - 5) / 5; // Scale to -1 to +1

  return Math.min(Math.max(score, 0), 10);
}

/**
 * Calculate value for money score (0-10)
 */
function calculateValueForMoneyScore(data: RawProductData): number {
  let score = 5.0;
  const price = data.price;

  // 1. Discount analysis (0-3 points)
  if (data.originalPrice && data.originalPrice > price) {
    const actualDiscount = (data.originalPrice - price) / data.originalPrice;
    score += Math.min(actualDiscount * 30, 3); // 10% discount = 0.3 points
  } else if (data.discountPercentage) {
    score += Math.min(data.discountPercentage / 100 * 3, 3);
  }

  // 2. Competitor price comparison (0-4 points)
  if (data.competitorPrices && data.competitorPrices.length > 0) {
    const avgCompetitorPrice = data.competitorPrices.reduce((a, b) => a + b) / data.competitorPrices.length;
    if (price < avgCompetitorPrice) {
      const savings = (avgCompetitorPrice - price) / avgCompetitorPrice;
      score += Math.min(savings * 8, 4); // 50% cheaper than competitors = 4 points
    } else if (price > avgCompetitorPrice * 1.5) {
      score -= 2; // Penalty for being 50% more expensive
    }
  }

  // 3. Quality to price ratio (0-3 points)
  // This would require quality score, so we'll estimate it
  const estimatedQuality = calculateQualityScore(data);
  const qualityPerDollar = estimatedQuality / Math.max(price, 1);
  
  // Normalize: Assume $100 product with quality 8 is good baseline
  const baseline = 8 / 100;
  const ratio = qualityPerDollar / baseline;
  score += Math.min(Math.max((ratio - 0.5) * 2, 0), 3); // Scale appropriately

  return Math.min(Math.max(score, 0), 10);
}

/**
 * Main scoring function
 */
export function scoreProduct(data: RawProductData): ProductScores {
  // Calculate all scores
  const quality = Math.round(calculateQualityScore(data) * 10) / 10;
  const durability = Math.round(calculateDurabilityScore(data) * 10) / 10;
  const valueForMoney = Math.round(calculateValueForMoneyScore(data) * 10) / 10;

  return {
    quality,
    durability,
    valueForMoney,
  };
}

lib/authenticity.ts interface SellerClassification {
  type: 'official' | 'authorized' | 'marketplace' | 'unknown';
  confidence: 'high' | 'medium' | 'low';
  reason: string;
}

interface KnownRetailer {
  domain: string;
  name: string;
  type: 'authorized' | 'marketplace';
}

const KNOWN_RETAILERS: KnownRetailer[] = [
  { domain: 'amazon.com', name: 'Amazon', type: 'marketplace' },
  { domain: 'walmart.com', name: 'Walmart', type: 'authorized' },
  { domain: 'target.com', name: 'Target', type: 'authorized' },
  { domain: 'bestbuy.com', name: 'Best Buy', type: 'authorized' },
  { domain: 'newegg.com', name: 'Newegg', type: 'marketplace' },
  { domain: 'ebay.com', name: 'eBay', type: 'marketplace' },
  { domain: 'aliexpress.com', name: 'AliExpress', type: 'marketplace' },
  { domain: 'alibaba.com', name: 'Alibaba', type: 'marketplace' },
  { domain: 'costco.com', name: 'Costco', type: 'authorized' },
  { domain: 'homedepot.com', name: 'Home Depot', type: 'authorized' },
  { domain: 'lowes.com', name: "Lowe's", type: 'authorized' },
  { domain: 'macys.com', name: "Macy's", type: 'authorized' },
  { domain: 'nordstrom.com', name: 'Nordstrom', type: 'authorized' },
  { domain: 'sephora.com', name: 'Sephora', type: 'authorized' },
  { domain: 'ulta.com', name: 'Ulta', type: 'authorized' },
  { domain: 'wayfair.com', name: 'Wayfair', type: 'marketplace' },
  { domain: 'etsy.com', name: 'Etsy', type: 'marketplace' },
  { domain: 'shopify.com', name: 'Shopify Store', type: 'marketplace' },
];

const OFFICIAL_INDICATORS = [
  'official',
  'official store',
  'brand store',
  'direct',
  'corporate',
  'headquarters',
];

const AUTHORIZED_INDICATORS = [
  'authorized',
  'authorized dealer',
  'authorized retailer',
  'certified',
  'certified reseller',
  'partner',
  'official partner',
];

export function classifySeller(
  url: string,
  brandName?: string,
  title?: string,
  description?: string
): SellerClassification {
  const normalizedUrl = url.toLowerCase();
  const domain = extractDomain(normalizedUrl);
  const normalizedTitle = title?.toLowerCase() || '';
  const normalizedDescription = description?.toLowerCase() || '';
  const normalizedBrand = brandName?.toLowerCase().replace(/\s+/g, '') || '';

  // Check if official brand domain
  if (brandName && isOfficialBrandDomain(domain, normalizedBrand)) {
    return {
      type: 'official',
      confidence: 'high',
      reason: 'Domain matches official brand website',
    };
  }

  // Check for official indicators in title/description
  if (hasOfficialIndicators(normalizedTitle, normalizedDescription)) {
    return {
      type: 'official',
      confidence: 'medium',
      reason: 'Contains official brand indicators',
    };
  }

  // Check known retailers
  const knownRetailer = KNOWN_RETAILERS.find((retailer) =>
    domain.includes(retailer.domain)
  );

  if (knownRetailer) {
    if (knownRetailer.type === 'authorized') {
      return {
        type: 'authorized',
        confidence: 'high',
        reason: `Known authorized retailer: ${knownRetailer.name}`,
      };
    }

    if (knownRetailer.type === 'marketplace') {
      // Check for authorized indicators on marketplace
      if (hasAuthorizedIndicators(normalizedTitle, normalizedDescription)) {
        return {
          type: 'marketplace',
          confidence: 'medium',
          reason: `Verified seller on ${knownRetailer.name}`,
        };
      }

      return {
        type: 'marketplace',
        confidence: 'low',
        reason: `Marketplace seller on ${knownRetailer.name}`,
      };
    }
  }

  // Check for authorized indicators without known retailer
  if (hasAuthorizedIndicators(normalizedTitle, normalizedDescription)) {
    return {
      type: 'authorized',
      confidence: 'medium',
      reason: 'Claims authorized retailer status',
    };
  }

  return {
    type: 'unknown',
    confidence: 'low',
    reason: 'Unable to verify seller authenticity',
  };
}

function extractDomain(url: string): string {
  try {
    const urlObj = new URL(url);
    return urlObj.hostname.replace('www.', '');
  } catch {
    return url;
  }
}

function isOfficialBrandDomain(domain: string, brandName: string): boolean {
  if (!brandName) return false;

  const brandSlug = brandName.replace(/[^a-z0-9]/g, '');
  const domainWithoutTLD = domain.split('.')[0];

  return (
    domain.includes(brandSlug) ||
    domainWithoutTLD === brandSlug ||
    brandSlug.includes(domainWithoutTLD)
  );
}

function hasOfficialIndicators(title: string, description: string): boolean {
  const combinedText = `${title} ${description}`;

  return OFFICIAL_INDICATORS.some((indicator) =>
    combinedText.includes(indicator)
  );
}

function hasAuthorizedIndicators(title: string, description: string): boolean {
  const combinedText = `${title} ${description}`;

  return AUTHORIZED_INDICATORS.some((indicator) =>
    combinedText.includes(indicator)
  );
}

export function classifyMultipleSellers(
  results: Array<{ url: string; title?: string; description?: string }>,
  brandName?: string
): Array<{ url: string; classification: SellerClassification }> {
  return results.map((result) => ({
    url: result.url,
    classification: classifySeller(
      result.url,
      brandName,
      result.title,
      result.description
    ),
  }));
}

export function filterByConfidence(
  classifications: Array<{ url: string; classification: SellerClassification }>,
  minConfidence: 'high' | 'medium' | 'low' = 'medium'
): Array<{ url: string; classification: SellerClassification }> {
  const confidenceLevels = { high: 3, medium: 2, low: 1 };
  const threshold = confidenceLevels[minConfidence];

  return classifications.filter(
    (item) => confidenceLevels[item.classification.confidence] >= threshold
  );
}

export function groupBySellerType(
  classifications: Array<{ url: string; classification: SellerClassification }>
): Record<string, Array<{ url: string; classification: SellerClassification }>> {
  return classifications.reduce((acc, item) => {
    const type = item.classification.type;
    if (!acc[type]) {
      acc[type] = [];
    }
    acc[type].push(item);
    return acc;
  }, {} as Record<string, Array<{ url: string; classification: SellerClassification }>>);
}

types/product.ts
