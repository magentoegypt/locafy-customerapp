# QA Follow-ups — Locafy Customer App

Blockers found during on-device QA of ClickUp **86d3f2jb6** (branch `claude/clickup-task-rksvlj`).
Both are **pre-existing** (not introduced by the QA-batch code changes) and each blocks further verification.
Device: Redmi (Android 16), staging API `stg.locafy.market`, test account `locafyqatest@gmail.com`.

---

## 0. Strong lead for item 1: `eg-en` REST rejects customer tokens  🔴 Backend

While working ClickUp **86d3g53f8** (checkout page), API probing on staging (2026-07-02) showed:

- `POST /rest/V1/integration/customer/token` (default store) → **works**, and the returned token works
  against `/rest/V1/customers/me`, `/rest/V1/carts/mine`, `/rest/V1/carts/mine/payment-methods` etc.
- The **same token** against the same endpoints under the store-code path the app uses —
  `/rest/eg-en/V1/customers/me`, `/rest/eg-en/V1/carts/mine` — always returns
  `{"message":"Specified request cannot be processed."}`.

The app builds all its REST URLs with the `eg-en` store code, so **every customer-token call the app
makes is failing at the store-view level**, which would fully explain item 1 below (add-to-cart 404 /
quote not found for logged-in customers). Backend should check the `eg-en` store-view webapi
configuration (integration/OAuth consumer availability per website, or a WAF rule scoped to that path).

Also noted while testing checkout parity:
- The website/backend applies **no tax** (`carts/mine/totals` → `tax_amount: 0`); the old in-app 14%
  line came from the app applying raw `taxRates/search` rates locally (now config-gated off).
- Website payment methods for a live quote: `sympl, cashondelivery, online, wallet, fawry_express,
  fawry_cards, fawry_cash` — the app renders the API list unfiltered/unreordered, so it matches.
- Email at checkout is optional on the website. The app now sends a fallback
  `guest<phone-digits>@locafy.market` when the shopper leaves email empty — if the website assigns a
  different default (server-side plugin), share the rule and we'll mirror it exactly.

---

## 1. Add-to-cart fails with backend 404 — checkout fully blocked  🔴 Backend

**Symptom**
Adding any product to the cart as a **logged-in** customer does nothing — the cart stays empty
("سلتك فارغة" / *Your cart is empty*), even though the app shows the "Added to bag" bottom sheet.

**Steps to reproduce**
1. Log in (or register) a customer.
2. Open any product → for a configurable product, select the variant (e.g. Top_size = M, All_color = Black).
3. Tap **Add to cart** or **Buy Now** → tap **Go to the shopping cart**.
4. Cart shows empty.

**Evidence (logcat)**
```
POST https://stg.locafy.market/eg-en/rest/V1/carts/mine/items
E flutter : [ERROR] Unhandled Exception: Not Found
E flutter : #2  CartModelMagento.addProductToCart  (cart_model_magento.dart:260:27)
E flutter : #3  ProductVariantMixin.addToCart       (product_variant_mixin.dart:455:19)
```

**Likely root cause**
`POST /V1/carts/mine/items` returns **404 Not Found** because the customer has **no active quote/cart**.
In Magento, a quote must exist first (create via `POST /V1/carts/mine`, which returns a cart id) before
items can be added. Either the quote isn't being created for (at least newly-registered) accounts on
staging, or the staging quote endpoint is misbehaving.

**Impact**
Checkout is **completely blocked** for logged-in customers. Because no item can enter the cart, none of
the Area F checkout fixes can be exercised or verified on device: *email optional*, *region shows name
(not "SG")*, *14% tax removal*, and *Back-to-Store → clears cart → Home*.

**Suggested actions**
- **Backend (primary):** confirm a quote/cart is created for a fresh customer on staging; verify
  `POST /carts/mine` then `POST /carts/mine/items` succeeds for `locafyqatest@gmail.com`.
- **Frontend (secondary):** ensure the app calls `POST /carts/mine` (create quote) before adding items
  if none exists; and handle the failure — the unhandled exception at `cart_model_magento.dart:260`
  currently still shows the optimistic "Added to bag" sheet, which misleads the user into thinking the
  add succeeded. Surface the error instead.

---

## 2. Account (حسابي) tab renders blank after opening a section WebView  🟠 Frontend

**Symptom**
The My-Account tab renders a blank white screen after opening an in-app WebView section and backing out.
Switching tabs does **not** recover it; only a full app restart restores the account content.

**Steps to reproduce**
1. Log in → open the **حسابي** (Account) tab (shows name + section list correctly).
2. Tap a section that opens an in-app WebView, e.g. **معلومات الحساب** (Account Information).
3. Back out.
4. Account tab is now blank. Switch Home ↔ Account — still blank.
5. Force-stop + relaunch the app → account tab shows correctly again.

**Likely root cause**
`lib/screens/settings/settings_screen.dart` uses a mutable `items` list to switch between the account
view and a drilled-in section's item list (`items = section.items`). After navigating into a WebView and
popping, the screen appears left in a state that renders nothing (stale/empty `items`, possibly held by
`AutomaticKeepAliveClientMixin`). Reset the `items` state on tab focus / when returning to the tab.

**Related (same area)**
The in-app **auth WebViews** for the Magento account pages (`/my-account`, Stored Payment Methods,
Newsletter, etc.) render **blank even when authenticated** — the page never displays in the WebView
(guest *or* logged-in). The Area D navigation fix correctly *opens* these pages; the *rendering* is a
separate in-app-WebView issue (session/cookie passing, JS, or a redirect-to-login that renders empty).

**Impact**
Confusing UX (account screen looks empty / requires restart); the WebView-backed account pages show no
content in-app.

**Suggested actions**
- Reset `settings_screen.dart` `items` state when the tab regains focus.
- Investigate why the Magento account pages don't render inside the in-app WebView (verify the auth
  cookie/session is passed and the page isn't silently redirecting to a blank login).

---

*Not a blocker, but noted:* `PlatformException: Failed to load FirebaseOptions from resource … values.xml`
appears on startup — Firebase isn't configured in this build (push/Firebase features off until
`google-services` values are added). App runs fine otherwise.
