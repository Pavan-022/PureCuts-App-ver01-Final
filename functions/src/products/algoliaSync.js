const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { defineSecret } = require("firebase-functions/params");
const algoliasearch = require("algoliasearch");
const admin = require("firebase-admin");

const ALGOLIA_APP_ID = defineSecret("ALGOLIA_APP_ID");
const ALGOLIA_ADMIN_API_KEY = defineSecret("ALGOLIA_ADMIN_API_KEY");

exports.onProductWriteToAlgolia = onDocumentWritten(
  {
    document: "products/{productId}",
    secrets: [ALGOLIA_APP_ID, ALGOLIA_ADMIN_API_KEY],
  },
  async (event) => {
    const productId = event.params.productId;
    const afterData = event.data?.after?.data() || null;

    const appId = ALGOLIA_APP_ID.value();
    const apiKey = ALGOLIA_ADMIN_API_KEY.value();

    if (!appId || !apiKey) {
      logger.error("[AlgoliaSync] Missing Algolia App ID or Admin API Key secret configuration.");
      return;
    }

    const client = algoliasearch(appId, apiKey);
    const index = client.initIndex("products");

    // Case 1: Product was deleted
    if (!afterData) {
      logger.info(`[AlgoliaSync] Deleting product ${productId} from index.`);
      try {
        await index.deleteObject(productId);
        logger.info(`[AlgoliaSync] Successfully deleted product ${productId} from index.`);
      } catch (error) {
        logger.error(`[AlgoliaSync] Failed to delete product ${productId} from Algolia:`, error);
      }
      return;
    }

    // Case 2: Product created or updated
    logger.info(`[AlgoliaSync] Syncing product ${productId} to index.`);
    try {
      const record = {
        objectID: productId,
        id: productId,
        name: afterData.name || afterData.title || afterData.productName || "",
        brand: afterData.brand || afterData.brandName || "",
        category: afterData.category || afterData.categoryName || "",
        subCategory: afterData.subCategory || afterData.subcategory || "",
        subSubCategory: afterData.subSubCategory || afterData.subsubCategory || "",
        tag: afterData.tag || "",
        tags: afterData.tags || [],
        description: afterData.description || afterData.shortDescription || "",
        subtitle: afterData.subtitle || afterData.subTitle || "",
        productType: afterData.productType || afterData.type || "",
        sku: afterData.sku || afterData.itemCode || "",
        price: afterData.price !== undefined ? Number(afterData.price) : 0,
        rating: afterData.rating !== undefined ? Number(afterData.rating) : 0,
        imageUrl: afterData.imageUrl || "",
        imagePath: afterData.imagePath || "",
        stock: afterData.stock !== undefined ? Number(afterData.stock) : 0,
        manageStock: afterData.manageStock !== false,
      };

      await index.saveObject(record);
      logger.info(`[AlgoliaSync] Successfully synced product ${productId} to index.`);
    } catch (error) {
      logger.error(`[AlgoliaSync] Failed to sync product ${productId} to Algolia:`, error);
    }
  }
);

exports.backfillProductsToAlgolia = onRequest(
  {
    secrets: [ALGOLIA_APP_ID, ALGOLIA_ADMIN_API_KEY],
  },
  async (req, res) => {
    logger.info("[AlgoliaSync] Starting manual backfill of all products.");
    try {
      const appId = ALGOLIA_APP_ID.value();
      const apiKey = ALGOLIA_ADMIN_API_KEY.value();

      if (!appId || !apiKey) {
        res.status(500).send("Algolia credentials are not configured in Secret Manager.");
        return;
      }

      const client = algoliasearch(appId, apiKey);
      const index = client.initIndex("products");

      if (!admin.apps.length) admin.initializeApp();
      const db = admin.firestore();

      const snapshot = await db.collection("products").get();
      if (snapshot.empty) {
        res.status(200).send("No products found in Firestore to sync.");
        return;
      }

      const records = [];
      snapshot.forEach((doc) => {
        const afterData = doc.data();
        records.push({
          objectID: doc.id,
          id: doc.id,
          name: afterData.name || afterData.title || afterData.productName || "",
          brand: afterData.brand || afterData.brandName || "",
          category: afterData.category || afterData.categoryName || "",
          subCategory: afterData.subCategory || afterData.subcategory || "",
          subSubCategory: afterData.subSubCategory || afterData.subsubCategory || "",
          tag: afterData.tag || "",
          tags: afterData.tags || [],
          description: afterData.description || afterData.shortDescription || "",
          subtitle: afterData.subtitle || afterData.subTitle || "",
          productType: afterData.productType || afterData.type || "",
          sku: afterData.sku || afterData.itemCode || "",
          price: afterData.price !== undefined ? Number(afterData.price) : 0,
          rating: afterData.rating !== undefined ? Number(afterData.rating) : 0,
          imageUrl: afterData.imageUrl || "",
          imagePath: afterData.imagePath || "",
          stock: afterData.stock !== undefined ? Number(afterData.stock) : 0,
          manageStock: afterData.manageStock !== false,
        });
      });

      await index.saveObjects(records);
      logger.info(`[AlgoliaSync] Backfill completed. Synced ${records.length} products.`);
      res.status(200).send(`Successfully synced ${records.length} products to Algolia!`);
    } catch (error) {
      logger.error("[AlgoliaSync] Backfill failed:", error);
      res.status(500).send("Failed to sync products: " + error.toString());
    }
  }
);
