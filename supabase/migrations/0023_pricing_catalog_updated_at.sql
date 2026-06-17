-- 0023_pricing_catalog_updated_at.sql
-- pricing_catalog_items (added in 0022) carries an updated_at column but was
-- never wired to the generic set_updated_at() BEFORE UPDATE trigger from 0005,
-- so an edited item kept its original timestamp. Attach the trigger to match
-- every other table that has updated_at.
CREATE TRIGGER pricing_catalog_items_set_updated_at
  BEFORE UPDATE ON pricing_catalog_items
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
