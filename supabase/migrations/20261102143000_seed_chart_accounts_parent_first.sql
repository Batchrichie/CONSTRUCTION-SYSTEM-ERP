-- Ensure the default chart is seeded in parent-before-child order.
-- A single INSERT ... SELECT cannot see grouping rows inserted by that same
-- statement, so child accounts must be inserted after their parent rows exist.

create or replace function private.seed_default_chart_of_accounts(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account record;
begin
  insert into public.chart_of_accounts
    (company_id, account_code, account_name, account_type, account_subtype,
     normal_balance, is_postable, is_control_account, allow_manual_journal,
     is_system_account, description)
  values
    (p_company_id,'1000','Assets','asset','assets','debit',false,false,false,true,'Asset accounts'),
    (p_company_id,'2000','Liabilities','liability','liabilities','credit',false,false,false,true,'Liability accounts'),
    (p_company_id,'3000','Equity','equity','equity','credit',false,false,false,true,'Equity accounts'),
    (p_company_id,'4000','Revenue','revenue','revenue','credit',false,false,false,true,'Revenue accounts'),
    (p_company_id,'5000','Direct Costs','expense','direct_costs','debit',false,false,false,true,'Direct project and contract costs'),
    (p_company_id,'6000','Operating Expenses','expense','operating_expenses','debit',false,false,false,true,'Operating and administrative expenses'),
    (p_company_id,'7000','Other Income','revenue','other_income','credit',false,false,false,true,'Non-core income'),
    (p_company_id,'8000','Finance Costs','expense','finance_costs','debit',false,false,false,true,'Finance and borrowing costs')
  on conflict (company_id, account_code) do nothing;

  -- Insert each account individually, ordered so parent groups are present
  -- before their children are resolved.
  for v_account in
    select *
    from (values
      ('1100','Current Assets','asset','current_asset','debit','1000',false,false,false,'Current asset grouping'),
      ('1110','Cash on Hand','asset','cash','debit','1100',true,false,true,'Cash held by the company'),
      ('1120','Bank Accounts','asset','bank','debit','1100',true,false,true,'Company bank balances'),
      ('1130','Mobile Money','asset','mobile_money','debit','1100',true,false,true,'Company mobile money balances'),
      ('1140','Trade Receivables','asset','trade_receivables','debit','1100',true,true,false,'Customer balances due'),
      ('1150','Contract Assets','asset','contract_assets','debit','1100',true,true,false,'Unconditional right to consideration not yet billed'),
      ('1160','Retention Receivable','asset','retention_receivable','debit','1100',true,true,false,'Retention receivable'),
      ('1200','Inventory','asset','inventory','debit','1000',false,false,false,'Inventory grouping'),
      ('1210','Construction Materials','asset','inventory_materials','debit','1200',true,true,false,'Construction materials held in stores'),
      ('1300','Work in Progress','asset','work_in_progress','debit','1000',true,true,false,'Eligible unrecognised contract costs'),
      ('1500','Property Plant and Equipment','asset','fixed_assets','debit','1000',true,false,true,'Property plant and equipment at cost'),
      ('1590','Accumulated Depreciation','asset','accumulated_depreciation','credit','1000',true,false,true,'Accumulated depreciation contra-asset'),
      ('2100','Current Liabilities','liability','current_liability','credit','2000',false,false,false,'Current liability grouping'),
      ('2110','Trade Payables','liability','trade_payables','credit','2100',true,true,false,'Supplier balances due'),
      ('2120','Accrued Expenses','liability','accruals','credit','2100',true,false,true,'Accrued expenses'),
      ('2130','VAT Payable','liability','vat_payable','credit','2100',true,true,false,'Output VAT payable'),
      ('2140','PAYE Payable','liability','paye_payable','credit','2100',true,true,false,'PAYE deductions payable'),
      ('2150','SSNIT and Pension Payable','liability','pension_payable','credit','2100',true,true,false,'Statutory pension deductions payable'),
      ('2160','Contract Liabilities and Customer Advances','liability','contract_liabilities','credit','2100',true,true,false,'Advance consideration and amounts billed ahead of performance'),
      ('2170','Retention Payable','liability','retention_payable','credit','2100',true,true,false,'Retention held from subcontractors'),
      ('2200','Long-term Liabilities','liability','long_term_liability','credit','2000',false,false,false,'Long-term liability grouping'),
      ('2210','Loans and Borrowings','liability','borrowings','credit','2200',true,false,true,'Borrowings and loans'),
      ('3100','Share Capital','equity','share_capital','credit','3000',true,false,true,'Issued share capital'),
      ('3200','Retained Earnings','equity','retained_earnings','credit','3000',true,false,false,'Accumulated retained earnings'),
      ('3300','Current Year Earnings','equity','current_year_earnings','credit','3000',true,false,false,'Current year result clearing account'),
      ('4100','Construction Contract Revenue','revenue','construction_revenue','credit','4000',true,false,true,'Recognised construction contract revenue'),
      ('4110','Architectural and Engineering Revenue','revenue','design_revenue','credit','4000',true,false,true,'Architectural and engineering design services'),
      ('4120','Real Estate Sales Revenue','revenue','real_estate_revenue','credit','4000',true,false,true,'Real estate unit sales'),
      ('4130','Other Operating Revenue','revenue','other_operating_revenue','credit','4000',true,false,true,'Other operating revenue'),
      ('5100','Construction Materials Consumed','expense','materials_cost','debit','5000',true,false,true,'Materials charged to projects'),
      ('5200','Direct Labour','expense','direct_labour','debit','5000',true,false,true,'Direct project labour'),
      ('5300','Subcontractor Costs','expense','subcontractor_cost','debit','5000',true,false,true,'Subcontractor and specialist works'),
      ('5400','Plant and Equipment Hire','expense','equipment_hire','debit','5000',true,false,true,'Plant and equipment hire'),
      ('5500','Site Expenses','expense','site_expenses','debit','5000',true,false,true,'Site running costs'),
      ('5600','Project Professional Fees','expense','project_professional_fees','debit','5000',true,false,true,'Project-related technical and professional costs'),
      ('6100','Administrative Salaries','expense','administrative_payroll','debit','6000',true,false,true,'Administrative staff costs'),
      ('6200','Rent and Utilities','expense','occupancy','debit','6000',true,false,true,'Office rent and utilities'),
      ('6300','Repairs and Maintenance','expense','repairs_maintenance','debit','6000',true,false,true,'Repairs and maintenance'),
      ('6400','Professional and Legal Fees','expense','professional_fees','debit','6000',true,false,true,'Legal, audit and advisory fees'),
      ('6500','Transport and Travel','expense','travel','debit','6000',true,false,true,'Transport and travel costs'),
      ('6600','Depreciation Expense','expense','depreciation','debit','6000',true,false,true,'Depreciation charge'),
      ('6700','Insurance Expense','expense','insurance','debit','6000',true,false,true,'Insurance premiums'),
      ('6800','Marketing and Business Development','expense','marketing','debit','6000',true,false,true,'Marketing and business development'),
      ('6900','General Office Expenses','expense','general_admin','debit','6000',true,false,true,'General office and administration'),
      ('7100','Interest and Investment Income','revenue','finance_income','credit','7000',true,false,true,'Interest and investment income'),
      ('8100','Interest Expense','expense','interest_expense','debit','8000',true,false,true,'Interest and finance charges'),
      ('8200','Bank and Payment Charges','expense','bank_charges','debit','8000',true,false,true,'Bank and payment charges')
    ) as x(account_code,account_name,account_type,account_subtype,normal_balance,parent_code,is_postable,is_control_account,allow_manual_journal,description)
    order by
      case when parent_code in ('1000','2000','3000','4000','5000','6000','7000','8000')
           then 1 else 2 end,
      account_code
  loop
    insert into public.chart_of_accounts
      (company_id, account_code, account_name, account_type, account_subtype,
       normal_balance, parent_account_id, is_postable, is_control_account,
       allow_manual_journal, is_system_account, description)
    select p_company_id, v_account.account_code, v_account.account_name,
           v_account.account_type, v_account.account_subtype,
           v_account.normal_balance, parent.id, v_account.is_postable,
           v_account.is_control_account, v_account.allow_manual_journal,
           true, v_account.description
    from public.chart_of_accounts parent
    where parent.company_id = p_company_id
      and parent.account_code = v_account.parent_code
    on conflict (company_id, account_code) do nothing;
  end loop;
end;
$$;
