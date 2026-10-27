# Olist E-Commerce: Delivery Performance and Customer Satisfaction

Do late deliveries drive bad reviews, where do the delays come from, and do they stop customers from buying again? I cleaned and analysed 96,203 delivered orders from a Brazilian marketplace in **PostgreSQL**, then built a six-page **Power BI** dashboard.

## Questions answered
1. How much worse do customers rate late orders?
2. Does a slow delivery hurt, or only a missed delivery date?
3. Where do the days go: seller handling or carrier transit?
4. Which states and months are worst?
5. Are the worst-rated categories and sellers delivery problems?
6. Does a late first order reduce repeat purchases?

## Dataset
[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) on Kaggle: real, anonymised orders from 2016 to 2018 in 9 CSV files (orders, items, payments, reviews, customers, products, sellers, geolocation, category translation). The CSVs can be found in this not in this Repository.

## Tools
- **PostgreSQL / SQL**: loading, cleaning, analysis queries and the views Power BI reads
- **Power BI**: data model, DAX measures, calculated columns and the dashboard


## What I did

### 1. SQL: clean and analyse
The raw tables had issues, so I cleaned them in SQL before any analysis:

| Raw data | What I did |
|---|---|
| 99,441 orders, but only 96,478 are `delivered` | Kept delivered orders only (lateness needs a delivery date) |
| 2,965 orders have no delivery date | Excluded them |
| Orders run Sep 2016 to Oct 2018 | Used full months, Jan 2017 to Aug 2018 |
| Some orders have several reviews | Kept the latest review per order |
| `customer_id` is new for every order | Used `customer_unique_id` to identify real customers |
| 610 products have no category | Labelled them `unknown` |

Result: **96,203 orders** in the analysis window. I then wrote the analysis queries (late vs on-time ratings, rating by days late, repeat purchase, seller concentration, late orders by state) and built four views for Power BI: `bi_orders`, `bi_items`, `bi_sellers`, `bi_retention`.

### 2. Power BI: model and dashboard
Power BI loads those four views as they are, with no Power Query transformations. In Power BI I added the relationships, the DAX measures (late %, average score, repeat %, carrier share of extra delay and more), a few calculated columns (such as Delivery Status and Delay Label), a Recommendations table, and the six dashboard pages.

## Data model
`bi_items` links to `bi_orders` (by `order_id`) and to `bi_sellers` (by `seller_id`).

Two tables are deliberately not connected:
- **Recommendations** is a static text table with nothing to join to.
- **bi_retention** is a one-row-per-customer cohort table built in SQL, used only for the retention chart and card. 

## Dashboard
1. **Executive Summary** ![Executive Summary](screenshots/01-executive-summary.png)
2. **Delivery vs Satisfaction** ![Delivery vs Satisfaction](screenshots/02-delivery-vs-satisfaction.png)
3. **Where the Delay Happens** ![Where the Delay Happens](screenshots/03-where-the-delay-happens.png)
4. **Geography** ![Geography](screenshots/04-geography.png)
5. **Categories and Sellers** ![Categories and Sellers](screenshots/05-categories-and-sellers.png)
6. **Recommendations** ![Recommendations](screenshots/06-recommendations.png)

## Key findings
- 6.8% of orders arrive late and average **2.27 stars vs 4.29** for on-time orders.
- Ratings drop a full star at just 1-3 days late. On-time orders that took 22+ days still score 3.9, so the promised date matters more than speed.
- About **87% of the extra delay on late orders is carrier transit**, not seller handling.
- RJ has a 12.1% late rate vs 4.5% in São Paulo and holds about 23% of all late orders.
- Office furniture has the most low ratings (25%) with a normal late rate (8%), so it points to product or listing quality.
- Only 3.1% of customers buy again within 180 days (2.7% after a late first order vs 3.1% after an on-time one). The gap is small and not statistically significant.

## Limitations

**What the dataset does not contain, so it was not analysed**
- No carrier names, so carriers cannot be compared. Carrier transit is measured as a total only.
- No returns, refunds or complaint reasons, so the cause of a bad review is unknown.

**Choices made in the analysis**
- Only delivered orders are analysed (Jan 2017 to Aug 2018). Jun to Aug 2018 may look better than it was because orders not yet delivered are excluded.
- 643 delivered orders have no review and are left out of rating figures.
- The data covers 20 months, so only one November peak is observed. Seasonality cannot be confirmed.
- Results show association, not proof of cause.

