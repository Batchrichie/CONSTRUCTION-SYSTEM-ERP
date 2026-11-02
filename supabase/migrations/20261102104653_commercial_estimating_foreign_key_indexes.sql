
-- Phase 5 supporting indexes for foreign-key joins and referential checks.
create index business_parties_created_by_idx
  on public.business_parties(created_by);
create index party_contacts_created_by_idx
  on public.party_contacts(created_by);
create index estimates_approved_by_idx
  on public.estimates(approved_by) where approved_by is not null;
create index estimates_created_by_idx
  on public.estimates(created_by);
create index estimate_items_company_estimate_section_fk_idx
  on public.estimate_items(company_id, estimate_id, section_id)
  where section_id is not null;
create index estimate_status_history_changed_by_idx
  on public.estimate_status_history(changed_by);
