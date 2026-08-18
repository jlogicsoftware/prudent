import {
  createAuthProvider,
  createDataProvider,
  LoginPage,
} from "@jzen/admin-core";
import { Admin, Resource } from "react-admin";
import { adminApiBase, authApiBase } from "./config";
import { UserEdit, UserList, UserShow } from "./resources/User";

/**
 * Prudent's admin panel. It assembles the framework scaffold (@jzen/admin-core) and registers
 * Prudent's own resources, typed off the generated OpenAPI schema. The API bases come from
 * ./config (the single place the REST prefix lives); the Vite dev proxy keeps them same-origin so
 * the session cookie flows.
 *
 * Only the "users" resource is registered (jZen's zen-identity AdminUserResource). Prudent's own
 * domain resources (accounts, categories, records) are user-scoped by design (ADR-001..010,
 * CLAUDE.md "every row is scoped to the JWT sub") — there is no cross-user listing endpoint for an
 * admin to browse, and building one is new product scope this phase does not ask for.
 */
const dataProvider = createDataProvider(adminApiBase);
const authProvider = createAuthProvider(authApiBase);

export function App() {
  return (
    <Admin
      dataProvider={dataProvider}
      authProvider={authProvider}
      loginPage={LoginPage}
    >
      <Resource name="users" list={UserList} show={UserShow} edit={UserEdit} />
    </Admin>
  );
}
