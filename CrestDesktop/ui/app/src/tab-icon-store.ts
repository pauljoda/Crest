/**
 * The images tabs wore, kept across launches, as the host's image store the
 * core leaves to its platforms (`SessionAdopted` names images "for the host's
 * image store; the core keeps none of them"). The Mac keeps them in its
 * FaviconAssets; here the interface keeps the last image each tab's page drew,
 * with the icon address it drew it for, so a tab whose page isn't loaded
 * after a relaunch still shows its site's icon, or, before its own page has
 * drawn one, the image another tab kept for the same address. A tab whose
 * address has moved on shows nothing stored until its page draws again.
 */

interface StoredIcon {
  readonly tabId: string;
  readonly address: string;
  readonly image: Uint8Array;
  readonly updated: number;
}

const databaseName = "crest-tab-icons";
const storeName = "icons";
/** More tabs than anyone keeps; the images used longest ago go first. */
const maximumCount = 1000;
const keptCount = 800;

let opened: Promise<IDBDatabase | null> | null = null;

function database(): Promise<IDBDatabase | null> {
  opened ??= new Promise((resolve) => {
    let request: IDBOpenDBRequest;
    try {
      request = indexedDB.open(databaseName, 2);
    } catch {
      resolve(null);
      return;
    }
    request.onupgradeneeded = () => {
      const store = request.result.objectStoreNames.contains(storeName)
        ? request.transaction!.objectStore(storeName)
        : request.result.createObjectStore(storeName, { keyPath: "tabId" });
      if (!store.indexNames.contains("updated")) store.createIndex("updated", "updated");
      if (!store.indexNames.contains("address")) store.createIndex("address", "address");
    };
    request.onsuccess = () => {
      const db = request.result;
      prune(db);
      resolve(db);
    };
    // Without storage the window keeps icons only while it runs.
    request.onerror = () => resolve(null);
  });
  return opened;
}

/** Forgets the images used longest ago once there are more than anyone keeps. */
function prune(db: IDBDatabase) {
  const transaction = db.transaction(storeName, "readwrite");
  const store = transaction.objectStore(storeName);
  const counted = store.count();
  counted.onsuccess = () => {
    let excess = counted.result - keptCount;
    if (counted.result <= maximumCount) return;
    store.index("updated").openCursor().onsuccess = (event) => {
      const cursor = (event.target as IDBRequest<IDBCursorWithValue | null>).result;
      if (!cursor || excess <= 0) return;
      cursor.delete();
      excess -= 1;
      cursor.continue();
    };
  };
}

/** The image `tabId` last wore for the icon at `address`, else one another tab kept for it, or null. */
export async function storedTabIcon(tabId: string, address: string): Promise<Uint8Array | null> {
  const db = await database();
  if (!db) return null;
  return new Promise((resolve) => {
    try {
      const store = db.transaction(storeName, "readonly").objectStore(storeName);
      const own = store.get(tabId);
      own.onsuccess = () => {
        const stored = own.result as StoredIcon | undefined;
        if (stored && stored.address === address) {
          resolve(stored.image);
          return;
        }
        const shared = store.index("address").get(address);
        shared.onsuccess = () => resolve((shared.result as StoredIcon | undefined)?.image ?? null);
        shared.onerror = () => resolve(null);
      };
      own.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
}

/** Keeps the image `tabId`'s page drew for the icon at `address`. */
export async function storeTabIcon(tabId: string, address: string, image: Uint8Array) {
  const db = await database();
  if (!db) return;
  try {
    const value: StoredIcon = { tabId, address, image, updated: Date.now() };
    db.transaction(storeName, "readwrite").objectStore(storeName).put(value);
  } catch {
    // An image that can't be kept is drawn again when its page next loads.
  }
}

/** Forgets the images kept for `tabIds`, as a deleted Space's tabs leave nothing behind. */
export async function forgetTabIcons(tabIds: readonly string[]) {
  const db = await database();
  if (!db || tabIds.length === 0) return;
  try {
    const store = db.transaction(storeName, "readwrite").objectStore(storeName);
    for (const tabId of tabIds) store.delete(tabId);
  } catch {
    // An image left behind is pruned with the oldest once the store fills.
  }
}
