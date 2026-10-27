# Olist: Delivery Performance and Customer Satisfaction

Do late deliveries drive bad reviews, where do the delays come from, and do they stop customers from buying again? I cleaned and analysed 96,203 delivered orders from a Brazilian marketplace in **PostgreSQL**, then built a six-page **Power BI** dashboard.

![Executive Summary](screenshots/01-executive-summary.png)

## Questions answered
1. How much worse do customers rate late orders?
2. Does a slow delivery hurt, or only a missed delivery date?
3. Where do the days go: seller handling or carrier transit?
4. Which states and months are worst?
5. Are the worst-rated categories and sellers delivery problems?
6. Does a late first order reduce repeat purchases?

## Dataset
[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) on Kaggle: real, anonymised orders from 2016 to 2018 in 9 CSV files (orders, items, payments, reviews, customers, products, sellers, geolocation, category translation). The CSVs are not in this repo; download them from Kaggle.

## Tools
- **PostgreSQL / SQL**: loading, cleaning, analysis queries and the views Power BI reads
- **Power BI**: data model, DAX measures, calculated columns and the dashboard

## Repository
```
README.md
sql/olist_analysis.sql      # full SQL workflow, run top to bottom
powerbi/olist_dashboard.pbix
screenshots/                # one image per dashboard page
```

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
- **bi_retention** is a one-row-per-customer cohort table built in SQL, used only for the retention chart and card. Because of this, the state slicer does not filter the retention numbers.

## Dashboard
1. **Executive Summary**: orders grew fast, late deliveries spiked twice, only about 3% of customers order again
2. **Delivery vs Satisfaction**: a missed delivery date hurts far more than a slow delivery
3. **Where the Delay Happens**: late spikes follow carrier transit, not seller handling
4. **Geography**: RJ and the northeast run 2-4x São Paulo's late rate
5. **Categories and Sellers**: the worst-rated categories are not delivery problems
6. **Recommendations**: fix carrier delays first; retention needs its own plan

## Key findings
- 6.8% of orders arrive late and average **2.27 stars vs 4.29** for on-time orders.
- Ratings drop a full star at just 1-3 days late. On-time orders that took 22+ days still score 3.9, so the promised date matters more than speed.
- About **87% of the extra delay on late orders is carrier transit**, not seller handling.
- RJ has a 12.1% late rate vs 4.5% in São Paulo and holds about 23% of all late orders.
- Office furniture has the most low ratings (25%) with a normal late rate (8%), so it points to product or listing quality.
- Only 3.1% of customers buy again within 180 days (2.7% after a late first order vs 3.1% after an on-time one). The gap is small and not statistically significant.

## Limitations
- Only delivered orders are analysed, so Jun to Aug 2018 may look better than it was.
- Results show association, not proof of cause. Review text was not analysed.
- The dataset has no carrier names, so carriers cannot be compared.
- The Power BI file reads from a local PostgreSQL database, so it cannot refresh without rebuilding that database.

## How to reproduce
1. Download the CSVs from Kaggle.
2. Create the tables and load the CSVs (Part 1 of the SQL file).
3. Run the rest of `sql/olist_analysis.sql` to create the views.
4. Open `powerbi/olist_dashboard.pbix`, or import the four `bi_*` views into a new report.
