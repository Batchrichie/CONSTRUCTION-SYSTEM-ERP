import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";
import ProjectsPage from "./ProjectsPage";
import ProjectBudgetsPage from "./ProjectBudgetsPage";
import EstimatesPage from "./EstimatesPage";
import ExpenseAllocationPage from "./ExpenseAllocationPage";

const authMocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
}));

vi.mock("../contexts/AuthContext", () => ({
  useAuth: () => ({
    client: { from: authMocks.from, rpc: authMocks.rpc },
    company: {
      id: "company-test",
      legal_name: "Test Construction Ltd",
      display_name: "Test Construction",
      base_currency: "GHS",
    },
    roleCode: "owner",
  }),
}));

const emptyTables: Record<string, unknown[]> = {};

function queryBuilder(data: unknown[] = []) {
  const result = { data, error: null };
  const builder: Record<string, unknown> = {};

  for (const method of [
    "select",
    "eq",
    "neq",
    "order",
    "limit",
    "in",
    "gte",
    "lte",
    "is",
    "not",
    "filter",
    "match",
  ]) {
    builder[method] = vi.fn(() => builder);
  }

  builder.single = vi.fn(() =>
    Promise.resolve({ data: data[0] ?? null, error: null }),
  );
  builder.maybeSingle = vi.fn(() =>
    Promise.resolve({ data: data[0] ?? null, error: null }),
  );
  builder.then = (
    resolve: (value: typeof result) => unknown,
    reject?: (reason: unknown) => unknown,
  ) => Promise.resolve(result).then(resolve, reject);

  return builder;
}

function renderPage(page: ReactNode) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <QueryClientProvider client={queryClient}>{page}</QueryClientProvider>,
  );
}

describe("core commercial and project pages", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.from.mockImplementation((table: string) =>
      queryBuilder(emptyTables[table] ?? []),
    );
    authMocks.rpc.mockResolvedValue({ data: null, error: null });
  });

  it("loads the project register for the authenticated company", async () => {
    renderPage(<ProjectsPage />);

    expect(
      screen.getByRole("heading", { name: "Projects" }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(authMocks.from).toHaveBeenCalledWith("projects"),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("loads project budget revisions without floating-point total errors", async () => {
    renderPage(<ProjectBudgetsPage />);

    expect(
      screen.getByRole("heading", { name: "Project Budgets" }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(authMocks.from).toHaveBeenCalledWith("project_budget_versions"),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("loads the estimates and BOQ register", async () => {
    renderPage(<EstimatesPage />);

    expect(
      screen.getByRole("heading", { name: "Estimates & BOQ" }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(authMocks.from).toHaveBeenCalledWith("estimate_totals"),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("loads expense allocation with no draft journals", async () => {
    renderPage(<ExpenseAllocationPage />);

    expect(
      screen.getByRole("heading", { name: "Expense Allocation" }),
    ).toBeInTheDocument();
    await waitFor(() =>
      expect(authMocks.from).toHaveBeenCalledWith("journal_entries"),
    );
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("opens and closes the expense recording workflow", async () => {
    renderPage(<ExpenseAllocationPage />);

    await waitFor(() =>
      expect(authMocks.from).toHaveBeenCalledWith("journal_entries"),
    );
    fireEvent.click(screen.getByRole("button", { name: /record expense/i }));

    expect(
      screen.getByRole("heading", { name: "Record project expense" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Payment / payable accounts")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(
      screen.queryByRole("heading", { name: "Record project expense" }),
    ).not.toBeInTheDocument();
  });

  it("opens the estimate creation modal from the estimates register", async () => {
    renderPage(<EstimatesPage />);

    await waitFor(() =>
      expect(authMocks.from).toHaveBeenCalledWith("estimate_totals"),
    );
    fireEvent.click(screen.getByRole("button", { name: /new estimate/i }));

    expect(
      screen.getByRole("heading", { name: "Create estimate" }),
    ).toBeInTheDocument();
    expect(screen.getByLabelText("Estimate title")).toBeInTheDocument();
  });
});
