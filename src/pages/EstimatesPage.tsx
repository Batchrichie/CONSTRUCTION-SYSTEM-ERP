import { useMemo, useState, type FormEvent } from "react";
import {
  ArrowLeft,
  ClipboardList,
  Plus,
  Send,
  CheckCircle2,
  XCircle,
  Trash2,
  Printer,
  Copy,
  Save,
  Edit2,
} from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "../contexts/AuthContext";
import Modal from "../components/Modal";
import { decimalUnits, sumUnits, unitsToNumber } from "../lib/decimalAmount";

type Customer = { id: string; legal_name: string; trading_name: string | null };
type Project = {
  id: string;
  project_code: string;
  name: string;
  customer_party_id: string | null;
  currency_code: string;
};
type Contract = {
  id: string;
  contract_ref: string;
  title: string;
  project_id: string;
  customer_party_id: string | null;
};
type Estimate = {
  id: string;
  estimate_number: string;
  revision_number: number;
  title: string;
  status: string;
  issue_date: string;
  valid_until: string | null;
  customer_party_id: string;
  project_id: string | null;
  project_contract_id: string | null;
  scope_notes: string | null;
  subtotal: number;
  discount_amount: number;
  tax_amount: number;
  total_amount: number;
  currency_code: string;
};
type Section = {
  id: string;
  section_number: number;
  title: string;
  description: string | null;
  sort_order: number;
};
type Item = {
  id: string;
  section_id: string | null;
  item_number: string;
  description: string;
  unit: string;
  quantity: number;
  unit_rate: number;
  line_total: number;
  item_type: string;
  sort_order: number;
};
const money = (n: number, currency = "GHS") =>
  new Intl.NumberFormat("en-GH", {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
  }).format(Number(n || 0));
const blankItem = {
  item_number: "",
  description: "",
  unit: "item",
  quantity: "1",
  unit_rate: "0",
  item_type: "work",
  section_id: "",
};
export default function EstimatesPage() {
  const { client, company, roleCode } = useAuth();
  const qc = useQueryClient();
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [showAddItem, setShowAddItem] = useState(false);
  const [showSection, setShowSection] = useState(false);
  const [form, setForm] = useState({
    estimate_number: "",
    title: "",
    customer_party_id: "",
    project_id: "",
    project_contract_id: "",
    issue_date: new Date().toISOString().slice(0, 10),
    valid_until: "",
    scope_notes: "",
  });
  const [sectionTitle, setSectionTitle] = useState("General works");
  const [item, setItem] = useState(blankItem);
  const [editingItem, setEditingItem] = useState<string | null>(null);
  const [editValues, setEditValues] = useState<Partial<Item>>({});
  const [adjustments, setAdjustments] = useState({
    discount_amount: "0",
    tax_amount: "0",
  });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const canApprove = ["owner", "admin", "project_manager"].includes(
    roleCode ?? "",
  );
  const customersQ = useQuery({
    queryKey: ["estimate-customers", company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from("business_parties")
        .select("id,legal_name,trading_name")
        .eq("company_id", company!.id)
        .eq("is_customer", true)
        .eq("status", "active")
        .order("legal_name");
      if (error) throw error;
      return (data ?? []) as Customer[];
    },
  });
  const projectsQ = useQuery({
    queryKey: ["estimate-projects", company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from("projects")
        .select("id,project_code,name,customer_party_id,currency_code")
        .eq("company_id", company!.id)
        .order("name");
      if (error) throw error;
      return (data ?? []) as Project[];
    },
  });
  const contractsQ = useQuery({
    queryKey: ["estimate-contracts", company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from("project_contracts")
        .select("id,contract_ref,title,project_id,customer_party_id")
        .eq("company_id", company!.id)
        .order("contract_ref");
      if (error) throw error;
      return (data ?? []) as Contract[];
    },
  });
  const estimatesQ = useQuery({
    queryKey: ["estimates", company?.id],
    enabled: Boolean(client && company),
    queryFn: async () => {
      const { data, error } = await client!
        .from("estimate_totals")
        .select("*")
        .eq("company_id", company!.id)
        .order("issue_date", { ascending: false });
      if (error) throw error;
      return (data ?? []) as Estimate[];
    },
  });
  const customers = customersQ.data ?? [],
    projects = projectsQ.data ?? [],
    contracts = contractsQ.data ?? [];
  const selected = estimatesQ.data?.find((e) => e.id === selectedId) ?? null;
  const sectionsQ = useQuery({
    queryKey: ["estimate-sections", company?.id, selectedId],
    enabled: Boolean(client && company && selectedId),
    queryFn: async () => {
      const { data, error } = await client!
        .from("estimate_sections")
        .select("id,section_number,title,description,sort_order")
        .eq("company_id", company!.id)
        .eq("estimate_id", selectedId!)
        .order("sort_order");
      if (error) throw error;
      return (data ?? []) as Section[];
    },
  });
  const itemsQ = useQuery({
    queryKey: ["estimate-items", company?.id, selectedId],
    enabled: Boolean(client && company && selectedId),
    queryFn: async () => {
      const { data, error } = await client!
        .from("estimate_items")
        .select(
          "id,section_id,item_number,description,unit,quantity,unit_rate,line_total,item_type,sort_order",
        )
        .eq("company_id", company!.id)
        .eq("estimate_id", selectedId!)
        .order("sort_order");
      if (error) throw error;
      return (data ?? []) as Item[];
    },
  });
  const sections = useMemo(() => sectionsQ.data ?? [], [sectionsQ.data]),
    items = useMemo(() => itemsQ.data ?? [], [itemsQ.data]);
  const grouped = useMemo(
    () =>
      sections.map((s) => ({
        ...s,
        items: items.filter((i) => i.section_id === s.id),
      })),
    [sections, items],
  );
  async function invalidateEstimate() {
    if (!company) return;
    await Promise.all([
      qc.invalidateQueries({ queryKey: ["estimates", company.id] }),
      qc.invalidateQueries({
        queryKey: ["estimate-items", company.id, selectedId],
      }),
      qc.invalidateQueries({
        queryKey: ["estimate-sections", company.id, selectedId],
      }),
    ]);
  }
  async function create(e: FormEvent) {
    e.preventDefault();
    if (!client || !company) return;
    setBusy(true);
    setError("");
    try {
      const { data, error } = await client
        .from("estimates")
        .insert({
          company_id: company.id,
          revision_number: 1,
          customer_party_id: form.customer_party_id,
          project_id: form.project_id || null,
          project_contract_id: form.project_contract_id || null,
          title: form.title.trim(),
          issue_date: form.issue_date,
          valid_until: form.valid_until || null,
          scope_notes: form.scope_notes.trim() || null,
          currency_code:
            projects.find((p) => p.id === form.project_id)?.currency_code ||
            company.base_currency ||
            "GHS",
        })
        .select("id")
        .single();
      if (error) throw error;
      await qc.invalidateQueries({ queryKey: ["estimates", company.id] });
      setSelectedId(data.id);
      setShowCreate(false);
      setForm({
        estimate_number: "",
        title: "",
        customer_party_id: "",
        project_id: "",
        project_contract_id: "",
        issue_date: new Date().toISOString().slice(0, 10),
        valid_until: "",
        scope_notes: "",
      });
    } catch (c) {
      setError(c instanceof Error ? c.message : "Could not create estimate.");
    } finally {
      setBusy(false);
    }
  }
  async function addSection(e?: FormEvent) {
    e?.preventDefault();
    if (!client || !company || !selected) return;
    setBusy(true);
    setError("");
    try {
      const { data, error } = await client
        .from("estimate_sections")
        .select("section_number")
        .eq("company_id", company.id)
        .eq("estimate_id", selected.id)
        .order("section_number", { ascending: false })
        .limit(1);
      if (error) throw error;
      const { error: insertError } = await client
        .from("estimate_sections")
        .insert({
          company_id: company.id,
          estimate_id: selected.id,
          section_number: (data?.[0]?.section_number ?? 0) + 1,
          title: sectionTitle.trim(),
          sort_order: sections.length,
        });
      if (insertError) throw insertError;
      setSectionTitle("General works");
      setShowSection(false);
      await qc.invalidateQueries({
        queryKey: ["estimate-sections", company.id, selected.id],
      });
    } catch (c) {
      setError(c instanceof Error ? c.message : "Could not add section.");
    } finally {
      setBusy(false);
    }
  }
  async function renameSection(s: Section) {
    if (!client || !company || !selected) return;
    const title = window.prompt("Section title", s.title);
    if (!title?.trim()) return;
    setBusy(true);
    try {
      const { error } = await client
        .from("estimate_sections")
        .update({ title: title.trim() })
        .eq("id", s.id)
        .eq("company_id", company.id);
      if (error) throw error;
      await qc.invalidateQueries({
        queryKey: ["estimate-sections", company.id, selected.id],
      });
    } catch (c) {
      setError(c instanceof Error ? c.message : "Could not update section.");
    } finally {
      setBusy(false);
    }
  }
  async function addItem(e: FormEvent) {
    e.preventDefault();
    if (!client || !company || !selected) return;
    if (!item.section_id) {
      setError("Choose the BOQ section for this item.");
      return;
    }
    const quantityUnits = decimalUnits(item.quantity);
    const unitRateUnits = decimalUnits(item.unit_rate);
    if (quantityUnits === null || quantityUnits <= 0n || unitRateUnits === null || unitRateUnits < 0n) {
      setError("Quantity must be positive and unit rate must be zero or greater, with no more than four decimal places.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const { error } = await client
        .from("estimate_items")
        .insert({
          company_id: company.id,
          estimate_id: selected.id,
          section_id: item.section_id,
          item_number: item.item_number.trim(),
          description: item.description.trim(),
          unit: item.unit.trim(),
          quantity: item.quantity,
          unit_rate: item.unit_rate,
          item_type: item.item_type,
          sort_order: items.length,
        });
      if (error) throw error;
      setItem(blankItem);
      setShowAddItem(false);
      await invalidateEstimate();
    } catch (c) {
      setError(c instanceof Error ? c.message : "Could not add BOQ item.");
    } finally {
      setBusy(false);
    }
  }
  async function saveItem(id: string) {
    if (!client || !company || !selected) return;
    const quantity = String(editValues.quantity ?? items.find((row) => row.id === id)?.quantity ?? "");
    const unitRate = String(editValues.unit_rate ?? items.find((row) => row.id === id)?.unit_rate ?? "");
    const quantityUnits = decimalUnits(quantity);
    const unitRateUnits = decimalUnits(unitRate);
    if (quantityUnits === null || quantityUnits <= 0n || unitRateUnits === null || unitRateUnits < 0n) {
      setError("Quantity must be positive and unit rate must be zero or greater, with no more than four decimal places.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const { error } = await client
        .from("estimate_items")
        .update({
          section_id: editValues.section_id || null,
          item_number: editValues.item_number,
          description: editValues.description,
          unit: editValues.unit,
          quantity,
          unit_rate: unitRate,
          item_type: editValues.item_type,
        })
        .eq("id", id)
        .eq("company_id", company.id);
      if (error) throw error;
      setEditingItem(null);
      setEditValues({});
      await invalidateEstimate();
    } catch (c) {
      setError(c instanceof Error ? c.message : "Could not update BOQ item.");
    } finally {
      setBusy(false);
    }
  }
  async function deleteItem(i: Item) {
    if (
      !client ||
      !company ||
      !selected ||
      !window.confirm("Delete this BOQ item?")
    )
      return;
    setBusy(true);
    try {
      const { error } = await client
        .from("estimate_items")
        .delete()
        .eq("id", i.id)
        .eq("company_id", company.id);
      if (error) throw error;
      await invalidateEstimate();
    } catch (c) {
      setError(c instanceof Error ? c.message : "Could not delete BOQ item.");
    } finally {
      setBusy(false);
    }
  }
  async function saveAdjustments() {
    if (!client || !company || !selected) return;
    const discountUnits = decimalUnits(adjustments.discount_amount);
    const taxUnits = decimalUnits(adjustments.tax_amount);
    const subtotalUnits = sumUnits(items.map((row) => row.line_total));
    if (discountUnits === null || discountUnits < 0n || taxUnits === null || taxUnits < 0n) {
      setError("Discount and tax must be non-negative amounts with no more than four decimal places.");
      return;
    }
    if (discountUnits > subtotalUnits) {
      setError("Discount cannot exceed the BOQ subtotal.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      const { error } = await client
        .from("estimates")
        .update({
          discount_amount: adjustments.discount_amount,
          tax_amount: adjustments.tax_amount,
        })
        .eq("id", selected.id)
        .eq("company_id", company.id);
      if (error) throw error;
      await qc.invalidateQueries({ queryKey: ["estimates", company.id] });
    } catch (c) {
      setError(
        c instanceof Error
          ? c.message
          : "Could not update estimate adjustments.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function transition(
    status: "submitted" | "approved" | "rejected" | "cancelled",
  ) {
    if (!client || !company || !selected) return;
    let note: string | null = null;
    if (status === "rejected") {
      note = window.prompt("Enter the reason for rejection:") ?? "";
      if (!note.trim()) return;
    }
    if (status === "cancelled" && !window.confirm("Cancel this estimate?"))
      return;
    setBusy(true);
    setError("");
    try {
      const { error } = await client.rpc("transition_estimate", {
        p_company_id: company.id,
        p_estimate_id: selected.id,
        p_new_status: status,
        p_note: note,
      });
      if (error) throw error;
      await qc.invalidateQueries({ queryKey: ["estimates", company.id] });
    } catch (c) {
      setError(c instanceof Error ? c.message : "Status update failed.");
    } finally {
      setBusy(false);
    }
  }
  async function cloneRevision() {
    if (!client || !company || !selected) return;
    setBusy(true);
    setError("");
    try {
      const { data, error } = await client.rpc("clone_estimate_revision", {
        p_company_id: company.id,
        p_estimate_id: selected.id,
      });
      if (error) throw error;
      await qc.invalidateQueries({ queryKey: ["estimates", company.id] });
      setSelectedId(data as string);
    } catch (c) {
      setError(c instanceof Error ? c.message : "Could not create revision.");
    } finally {
      setBusy(false);
    }
  }
  if (selected) {
    const subtotal = unitsToNumber(sumUnits(items.map((i) => i.line_total)));
    const customer = customers.find((c) => c.id === selected.customer_party_id);
    const project = projects.find((p) => p.id === selected.project_id);
    const contract = contracts.find(
      (c) => c.id === selected.project_contract_id,
    );
    return (
      <div className="page-content estimate-document">
        <button
          className="back-button no-print"
          onClick={() => setSelectedId(null)}
        >
          <ArrowLeft size={15} /> All estimates
        </button>
        <div className="workspace-heading no-print">
          <div>
            <p className="eyebrow">
              ESTIMATE / {selected.estimate_number} · REV{" "}
              {selected.revision_number}
            </p>
            <h1>{selected.title}</h1>
            <p className="page-subtitle">
              Issue date {selected.issue_date} · {selected.currency_code}
            </p>
          </div>
          <div className="estimate-toolbar">
            <span className={"estimate-status " + selected.status}>
              {selected.status}
            </span>
            <button className="outline-button" onClick={() => window.print()}>
              <Printer size={14} /> Print
            </button>
            {["approved", "rejected"].includes(selected.status) && (
              <button
                className="outline-button"
                disabled={busy}
                onClick={() => void cloneRevision()}
              >
                <Copy size={14} /> New revision
              </button>
            )}
          </div>
        </div>
        <div className="print-only">
          <h1>ESTIMATE</h1>
          <p>
            {selected.estimate_number} · Revision {selected.revision_number} ·{" "}
            {selected.issue_date}
          </p>
          <h2>{selected.title}</h2>
        </div>
        {error && <div className="form-alert error no-print">{error}</div>}
        <section className="data-panel estimate-summary">
          <div>
            <span>Customer</span>
            <strong>
              {customer?.trading_name || customer?.legal_name || "Customer"}
            </strong>
          </div>
          <div>
            <span>Project</span>
            <strong>
              {project
                ? project.project_code + " · " + project.name
                : "Not linked"}
            </strong>
          </div>
          <div>
            <span>Contract</span>
            <strong>
              {contract
                ? contract.contract_ref + " · " + contract.title
                : "Not linked"}
            </strong>
          </div>
          <div>
            <span>Subtotal</span>
            <strong>{money(subtotal, selected.currency_code)}</strong>
          </div>
          <div>
            <span>Total</span>
            <strong>
              {money(Number(selected.total_amount), selected.currency_code)}
            </strong>
          </div>
        </section>
        {selected.status === "draft" && (
          <>
            <section className="form-panel no-print">
              <div className="panel-heading">
                <div>
                  <h2>BOQ structure</h2>
                  <p>
                    Add sections, then place each item under the correct
                    section.
                  </p>
                </div>
              </div>
              <div className="section-chip-list">
                {sections.map((s) => (
                  <button
                    className="outline-button"
                    key={s.id}
                    onClick={() => void renameSection(s)}
                  >
                    {s.section_number}. {s.title} <Edit2 size={12} />
                  </button>
                ))}
              </div>
              <div className="estimate-toolbar">
                <button
                  className="outline-button"
                  onClick={() => {
                    setSectionTitle("General works");
                    setShowSection(true);
                  }}
                >
                  <Plus size={14} /> Add section
                </button>
                <button
                  className="primary-button"
                  disabled={sections.length === 0}
                  onClick={() => setShowAddItem(true)}
                >
                  <Plus size={14} /> Add BOQ item
                </button>
              </div>
              {showSection && (
                <Modal
                  title="Add BOQ section"
                  description="Create a section to organise related quantities and rates."
                  eyebrow="BILL OF QUANTITIES"
                  onClose={() => setShowSection(false)}
                  closeDisabled={busy}
                >
                  <form className="data-form" onSubmit={addSection}>
                    <label className="form-wide">
                      Section name
                      <input
                        required
                        autoFocus
                        value={sectionTitle}
                        onChange={(e) => setSectionTitle(e.target.value)}
                        placeholder="e.g. Substructure"
                      />
                    </label>
                    {error && (
                      <div className="form-alert error form-wide">{error}</div>
                    )}
                    <div className="form-actions form-wide">
                      <button
                        type="button"
                        className="outline-button"
                        onClick={() => setShowSection(false)}
                        disabled={busy}
                      >
                        Cancel
                      </button>
                      <button
                        className="primary-button"
                        disabled={busy || !sectionTitle.trim()}
                      >
                        {busy ? "Saving…" : "Add section"}
                      </button>
                    </div>
                  </form>
                </Modal>
              )}
              {showAddItem && (
                <Modal
                  title="Add BOQ item"
                  description="Enter the quantity and rate. The database calculates the line amount."
                  eyebrow="BILL OF QUANTITIES"
                  size="large"
                  onClose={() => setShowAddItem(false)}
                  closeDisabled={busy}
                >
                  <form className="data-form boq-form" onSubmit={addItem}>
                    <label>
                      Section
                      <select
                        required
                        value={item.section_id}
                        onChange={(e) =>
                          setItem({ ...item, section_id: e.target.value })
                        }
                      >
                        <option value="">Select section</option>
                        {sections.map((s) => (
                          <option key={s.id} value={s.id}>
                            {s.section_number}. {s.title}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Item no.
                      <input
                        required
                        value={item.item_number}
                        onChange={(e) =>
                          setItem({ ...item, item_number: e.target.value })
                        }
                      />
                    </label>
                    <label className="form-wide">
                      Description
                      <input
                        required
                        value={item.description}
                        onChange={(e) =>
                          setItem({ ...item, description: e.target.value })
                        }
                      />
                    </label>
                    <label>
                      Type
                      <select
                        value={item.item_type}
                        onChange={(e) =>
                          setItem({ ...item, item_type: e.target.value })
                        }
                      >
                        {[
                          "work",
                          "material",
                          "labour",
                          "equipment",
                          "subcontract",
                          "provisional_sum",
                          "prime_cost",
                          "other",
                        ].map((t) => (
                          <option key={t} value={t}>
                            {t.replace("_", " ")}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Unit
                      <input
                        required
                        value={item.unit}
                        onChange={(e) =>
                          setItem({ ...item, unit: e.target.value })
                        }
                      />
                    </label>
                    <label>
                      Quantity
                      <input
                        required
                        type="number"
                        min="0.0001"
                        step="0.0001"
                        value={item.quantity}
                        onChange={(e) =>
                          setItem({ ...item, quantity: e.target.value })
                        }
                      />
                    </label>
                    <label>
                      Rate
                      <input
                        required
                        type="number"
                        min="0"
                        step="0.0001"
                        value={item.unit_rate}
                        onChange={(e) =>
                          setItem({ ...item, unit_rate: e.target.value })
                        }
                      />
                    </label>
                    <div className="form-actions form-wide">
                      <button
                        type="button"
                        className="outline-button"
                        onClick={() => setShowAddItem(false)}
                        disabled={busy}
                      >
                        Cancel
                      </button>
                      <button
                        className="primary-button"
                        disabled={busy || sections.length === 0}
                      >
                        {busy ? "Adding…" : "Add BOQ item"}
                      </button>
                    </div>
                  </form>
                </Modal>
              )}
            </section>
            <section className="form-panel no-print">
              <div className="panel-heading">
                <div>
                  <h2>Commercial adjustments</h2>
                  <p>
                    Manual estimate values only; tax is not a Ghana VAT
                    computation.
                  </p>
                </div>
              </div>
              <div className="adjustment-form">
                <label>
                  Discount amount
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={adjustments.discount_amount}
                    onChange={(e) =>
                      setAdjustments({
                        ...adjustments,
                        discount_amount: e.target.value,
                      })
                    }
                  />
                </label>
                <label>
                  Tax amount
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={adjustments.tax_amount}
                    onChange={(e) =>
                      setAdjustments({
                        ...adjustments,
                        tax_amount: e.target.value,
                      })
                    }
                  />
                </label>
                <button
                  className="primary-button"
                  disabled={busy}
                  onClick={() => void saveAdjustments()}
                >
                  <Save size={14} /> Save adjustments
                </button>
              </div>
            </section>
          </>
        )}
        <section className="data-panel">
          <div className="panel-heading">
            <div>
              <h2>Bill of quantities</h2>
              <p>Line totals are generated by the database.</p>
            </div>
          </div>
          {itemsQ.isLoading || sectionsQ.isLoading ? (
            <div className="table-empty">Loading BOQ…</div>
          ) : items.length === 0 ? (
            <div className="table-empty">
              <ClipboardList size={25} />
              <strong>No BOQ items yet</strong>
              <span>
                Add a section and priced items to build this estimate.
              </span>
            </div>
          ) : (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Item</th>
                    <th>Description</th>
                    <th>Unit</th>
                    <th className="numeric">Qty</th>
                    <th className="numeric">Rate</th>
                    <th className="numeric">Amount</th>
                    <th className="no-print" />
                  </tr>
                </thead>
                {grouped.map((s) => (
                  <tbody key={s.id}>
                    <tr className="boq-section-row">
                      <td colSpan={7}>
                        {s.section_number}. {s.title}
                      </td>
                    </tr>
                    {s.items.map((i) => (
                      <tr key={i.id}>
                        {editingItem === i.id ? (
                          <>
                            <td>
                              <input
                                value={String(
                                  editValues.item_number ?? i.item_number,
                                )}
                                onChange={(e) =>
                                  setEditValues({
                                    ...editValues,
                                    item_number: e.target.value,
                                  })
                                }
                              />
                            </td>
                            <td>
                              <input
                                value={String(
                                  editValues.description ?? i.description,
                                )}
                                onChange={(e) =>
                                  setEditValues({
                                    ...editValues,
                                    description: e.target.value,
                                  })
                                }
                              />
                              <select
                                value={String(
                                  editValues.section_id ?? i.section_id ?? "",
                                )}
                                onChange={(e) =>
                                  setEditValues({
                                    ...editValues,
                                    section_id: e.target.value,
                                  })
                                }
                              >
                                {sections.map((x) => (
                                  <option key={x.id} value={x.id}>
                                    {x.title}
                                  </option>
                                ))}
                              </select>
                            </td>
                            <td>
                              <input
                                value={String(editValues.unit ?? i.unit)}
                                onChange={(e) =>
                                  setEditValues({
                                    ...editValues,
                                    unit: e.target.value,
                                  })
                                }
                              />
                            </td>
                            <td>
                              <input
                                type="number"
                                step="0.0001"
                                value={String(
                                  editValues.quantity ?? i.quantity,
                                )}
                                onChange={(e) =>
                                  setEditValues({
                                    ...editValues,
                                    quantity: e.target
                                      .value as unknown as number,
                                  })
                                }
                              />
                            </td>
                            <td>
                              <input
                                type="number"
                                step="0.0001"
                                value={String(
                                  editValues.unit_rate ?? i.unit_rate,
                                )}
                                onChange={(e) =>
                                  setEditValues({
                                    ...editValues,
                                    unit_rate: e.target
                                      .value as unknown as number,
                                  })
                                }
                              />
                            </td>
                            <td className="numeric">
                              {money(
                                Number(editValues.quantity ?? i.quantity) *
                                  Number(editValues.unit_rate ?? i.unit_rate),
                                selected.currency_code,
                              )}
                            </td>
                            <td className="no-print">
                              <button
                                className="text-button"
                                onClick={() => void saveItem(i.id)}
                              >
                                Save
                              </button>
                              <button
                                className="text-button"
                                onClick={() => setEditingItem(null)}
                              >
                                Cancel
                              </button>
                            </td>
                          </>
                        ) : (
                          <>
                            <td>{i.item_number}</td>
                            <td>
                              <strong>{i.description}</strong>
                              <small>{i.item_type.replace("_", " ")}</small>
                            </td>
                            <td>{i.unit}</td>
                            <td className="numeric">
                              {Number(i.quantity).toLocaleString("en-GH")}
                            </td>
                            <td className="numeric">
                              {money(
                                Number(i.unit_rate),
                                selected.currency_code,
                              )}
                            </td>
                            <td className="numeric">
                              {money(
                                Number(i.line_total),
                                selected.currency_code,
                              )}
                            </td>
                            <td className="no-print">
                              {selected.status === "draft" && (
                                <>
                                  <button
                                    className="text-button"
                                    onClick={() => {
                                      setEditingItem(i.id);
                                      setEditValues({ ...i });
                                    }}
                                  >
                                    Edit
                                  </button>
                                  <button
                                    className="text-button danger-text"
                                    onClick={() => void deleteItem(i)}
                                  >
                                    Delete
                                  </button>
                                </>
                              )}
                            </td>
                          </>
                        )}
                      </tr>
                    ))}
                  </tbody>
                ))}
                <tfoot>
                  <tr>
                    <td colSpan={5}>BOQ subtotal</td>
                    <td className="numeric">
                      {money(subtotal, selected.currency_code)}
                    </td>
                    <td />
                  </tr>
                  <tr>
                    <td colSpan={5}>Discount</td>
                    <td className="numeric">
                      {money(
                        Number(selected.discount_amount),
                        selected.currency_code,
                      )}
                    </td>
                    <td />
                  </tr>
                  <tr>
                    <td colSpan={5}>Tax input*</td>
                    <td className="numeric">
                      {money(
                        Number(selected.tax_amount),
                        selected.currency_code,
                      )}
                    </td>
                    <td />
                  </tr>
                  <tr>
                    <td colSpan={5}>Estimate total</td>
                    <td className="numeric">
                      {money(
                        Number(selected.total_amount),
                        selected.currency_code,
                      )}
                    </td>
                    <td />
                  </tr>
                </tfoot>
              </table>
            </div>
          )}
        </section>
        {selected.scope_notes && (
          <section className="data-panel">
            <h2>Scope notes</h2>
            <p>{selected.scope_notes}</p>
          </section>
        )}
        <div className="estimate-actions no-print">
          {selected.status === "draft" && (
            <button
              className="primary-button"
              disabled={busy || items.length === 0}
              onClick={() => void transition("submitted")}
            >
              <Send size={14} /> Submit for approval
            </button>
          )}
          {selected.status === "submitted" && canApprove && (
            <>
              <button
                className="primary-button"
                disabled={busy}
                onClick={() => void transition("approved")}
              >
                <CheckCircle2 size={14} /> Approve
              </button>
              <button
                className="outline-button danger-button"
                disabled={busy}
                onClick={() => void transition("rejected")}
              >
                <XCircle size={14} /> Reject
              </button>
            </>
          )}
          {["draft", "rejected"].includes(selected.status) && (
            <button
              className="outline-button danger-button"
              disabled={busy}
              onClick={() => void transition("cancelled")}
            >
              <Trash2 size={14} /> Cancel estimate
            </button>
          )}
        </div>
        <p className="page-footnote no-print">
          * Tax is a manual commercial estimate input only. It is not a Ghana
          VAT calculation, tax return value or accounting posting.
        </p>
      </div>
    );
  }
  return (
    <div className="page-content">
      <div className="workspace-heading">
        <div>
          <p className="eyebrow">COMMERCIAL MANAGEMENT</p>
          <h1>Estimates & BOQ</h1>
          <p className="page-subtitle">
            Prepare priced scopes of work, revisions and controlled approvals.
          </p>
        </div>
        <button
          className="primary-button"
          onClick={() => {
            setError("");
            setShowCreate(true);
          }}
        >
          <Plus size={15} /> New estimate
        </button>
      </div>
      {showCreate && (
        <Modal
          title="Create estimate"
          description="Set up the commercial details. The estimate will be saved as a draft."
          eyebrow="COMMERCIAL MANAGEMENT"
          size="large"
          onClose={() => setShowCreate(false)}
          closeDisabled={busy}
        >
          <form className="data-form" onSubmit={create}>
            <label>
              Estimate number
              <input value="Generated automatically on save" readOnly />
            </label>
            <label>
              Estimate title
              <input
                required
                minLength={2}
                maxLength={200}
                value={form.title}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
                placeholder="Proposed office block construction"
              />
            </label>
            <label>
              Customer
              <select
                required
                value={form.customer_party_id}
                onChange={(e) =>
                  setForm({
                    ...form,
                    customer_party_id: e.target.value,
                    project_id: "",
                    project_contract_id: "",
                  })
                }
              >
                <option value="">Select customer</option>
                {customers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.trading_name || c.legal_name}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Project (optional)
              <select
                value={form.project_id}
                onChange={(e) =>
                  setForm({
                    ...form,
                    project_id: e.target.value,
                    project_contract_id: "",
                  })
                }
              >
                <option value="">No project linked</option>
                {projects
                  .filter(
                    (p) =>
                      !p.customer_party_id ||
                      p.customer_party_id === form.customer_party_id,
                  )
                  .map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.project_code} · {p.name}
                    </option>
                  ))}
              </select>
            </label>
            <label>
              Contract (optional)
              <select
                value={form.project_contract_id}
                onChange={(e) =>
                  setForm({ ...form, project_contract_id: e.target.value })
                }
              >
                <option value="">No contract linked</option>
                {contracts
                  .filter(
                    (c) =>
                      (!form.project_id || c.project_id === form.project_id) &&
                      (!c.customer_party_id ||
                        c.customer_party_id === form.customer_party_id),
                  )
                  .map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.contract_ref} · {c.title}
                    </option>
                  ))}
              </select>
            </label>
            <label>
              Issue date
              <input
                type="date"
                required
                value={form.issue_date}
                onChange={(e) =>
                  setForm({ ...form, issue_date: e.target.value })
                }
              />
            </label>
            <label>
              Valid until
              <input
                type="date"
                min={form.issue_date}
                value={form.valid_until}
                onChange={(e) =>
                  setForm({ ...form, valid_until: e.target.value })
                }
              />
            </label>
            <label className="form-wide">
              Scope notes
              <textarea
                rows={3}
                value={form.scope_notes}
                onChange={(e) =>
                  setForm({ ...form, scope_notes: e.target.value })
                }
              />
            </label>
            {customers.length === 0 && (
              <p className="form-wide helper-text">
                Create an active customer in Customers & Suppliers before
                preparing an estimate.
              </p>
            )}
            {error && <div className="form-alert error form-wide">{error}</div>}
            <div className="form-actions form-wide">
              <button
                type="button"
                className="outline-button"
                onClick={() => setShowCreate(false)}
              >
                Cancel
              </button>
              <button
                className="primary-button"
                disabled={busy || customers.length === 0}
              >
                {busy ? "Creating…" : "Create draft estimate"}
              </button>
            </div>
          </form>
        </Modal>
      )}
      <section className="data-panel">
        <div className="list-toolbar">
          <div>
            <strong className="section-title">Estimate register</strong>
            <span className="subtle-count">
              {estimatesQ.data?.length ?? 0} records
            </span>
          </div>
        </div>
        {estimatesQ.isLoading ? (
          <div className="table-empty">Loading estimates…</div>
        ) : estimatesQ.error ? (
          <div className="table-empty error-text">
            {(estimatesQ.error as Error).message}
          </div>
        ) : (estimatesQ.data ?? []).length === 0 ? (
          <div className="table-empty">
            <ClipboardList size={25} />
            <strong>No estimates created</strong>
            <span>Create a draft estimate and add its BOQ.</span>
          </div>
        ) : (
          <div className="table-scroll">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Estimate</th>
                  <th>Customer</th>
                  <th>Project</th>
                  <th>Date</th>
                  <th>Status</th>
                  <th className="numeric">Total</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {estimatesQ.data!.map((e) => (
                  <tr
                    key={e.id}
                    className="clickable-row"
                    onClick={() => {
                      setSelectedId(e.id);
                      setAdjustments({
                        discount_amount: String(e.discount_amount),
                        tax_amount: String(e.tax_amount),
                      });
                    }}
                  >
                    <td>
                      <strong>
                        {e.estimate_number} / Rev {e.revision_number}
                      </strong>
                      <small>{e.title}</small>
                    </td>
                    <td>
                      {customers.find((c) => c.id === e.customer_party_id)
                        ?.trading_name ||
                        customers.find((c) => c.id === e.customer_party_id)
                          ?.legal_name ||
                        "—"}
                    </td>
                    <td>
                      {projects.find((p) => p.id === e.project_id)
                        ?.project_code || "—"}
                    </td>
                    <td>{e.issue_date}</td>
                    <td>
                      <span className={"estimate-status " + e.status}>
                        {e.status}
                      </span>
                    </td>
                    <td className="numeric">
                      {money(Number(e.total_amount), e.currency_code)}
                    </td>
                    <td>
                      <button
                        className="text-button"
                        onClick={(ev) => {
                          ev.stopPropagation();
                          setSelectedId(e.id);
                          setAdjustments({
                            discount_amount: String(e.discount_amount),
                            tax_amount: String(e.tax_amount),
                          });
                        }}
                      >
                        Open →
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
