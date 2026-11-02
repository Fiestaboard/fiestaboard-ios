import Foundation

/// The editor's catalog reads (PLAN §2.3 "Catalogs", B21/B22). All are reads or a non-mutating
/// validation POST; none is retried by the caller. `/v1/*` accepts the session like every route;
/// `/plugins/*` and `/templates/*` are internal (cookie).
public protocol TemplateCatalogReading: Sendable {
    /// Raw `GET /v1/variables`.
    func templateVariablesData() async throws -> Data
    /// Raw `GET /plugins/{id}/manifest`.
    func pluginManifestData(id: String) async throws -> Data
    /// `GET /v1/functions`.
    func formulaFunctions() async throws -> FunctionCatalog
    /// `POST /templates/validate {template: [row]}` (no board: formulas validate the same everywhere).
    func validateTemplateRows(_ rows: [String]) async throws -> TemplateValidationResult
}

extension TemplateCatalogReading {
    /// The variables plus every plugin's manifest (name, icon, arrays). A manifest that can't be
    /// read leaves that plugin with its Title Case id and no icon; the catalog still loads.
    public func templateCatalog() async throws -> TemplateCatalog {
        let data = try await templateVariablesData()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let variables = object["variables"] as? [String: Any] else { throw FiestaBoardError.invalidResponse }
        let ids = variables.keys.filter(DeploymentURL.validSegment)
        let manifests = await withTaskGroup(of: (String, TemplateCatalog.Manifest?).self) { group in
            for id in ids {
                group.addTask {
                    guard let raw = try? await self.pluginManifestData(id: id) else { return (id, nil) }
                    return (id, try? TemplateCatalog.Manifest(data: raw))
                }
            }
            var result: [String: TemplateCatalog.Manifest] = [:]
            for await (id, manifest) in group { if let manifest { result[id] = manifest } }
            return result
        }
        return try TemplateCatalog(variablesData: data, manifests: manifests)
    }

    /// One formula's verdict: the expression wrapped as `{{= … }}`.
    public func validateFormula(_ expression: String) async throws -> FormulaCheck {
        FormulaCheck(try await validateTemplateRows(["{{= \(expression) }}"]))
    }
}

extension LiveFiestaBoardService: TemplateCatalogReading {
    private func readOK(_ request: APIRequest) async throws -> Data {
        let result = try await response(request)
        guard result.status == 200 else { throw FiestaBoardError.rejected(status: result.status) }
        return result.data
    }
    public func templateVariablesData() async throws -> Data {
        try await readOK(APIRequest(path: ["v1", "variables"], cachePolicy: .noStore))
    }
    public func pluginManifestData(id: String) async throws -> Data {
        guard DeploymentURL.validSegment(id) else { throw FiestaBoardError.invalidPath }
        return try await readOK(APIRequest(path: ["plugins", id, "manifest"], cachePolicy: .noStore))
    }
    public func formulaFunctions() async throws -> FunctionCatalog {
        try FunctionCatalog(data: try await readOK(APIRequest(path: ["v1", "functions"], cachePolicy: .noStore)))
    }
    public func validateTemplateRows(_ rows: [String]) async throws -> TemplateValidationResult {
        struct Body: Encodable { let template: [String] }
        let data = try await readOK(APIRequest(.post, path: ["templates", "validate"], body: JSONEncoder().encode(Body(template: rows))))
        return try TemplateValidationResult(rawData: data)
    }
}
