import Foundation

/// Authenticated Compose picker reads bound to the captured principal and display.
/// Array hydration is deliberately excluded: the recorded mobile scope denies it.
public protocol ComposeCatalogReading: Sendable {
    func composeTemplateCatalog(_ request: ComposeRequest) async throws -> TemplateCatalog
    func composeFormulaFunctions(_ request: ComposeRequest) async throws -> FunctionCatalog
    func validateComposeFormula(_ expression: String, request: ComposeRequest) async throws -> FormulaCheck
}

extension LiveFiestaBoardService: ComposeCatalogReading {}

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
    /// Raw `POST /displays/raw/batch {display_types, enabled_only: true}` (W4): live plugin data
    /// for array items, as the web picker reads it.
    func displaysRawBatchData(ids: [String]) async throws -> Data
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
        // Plugins whose manifest declares arrays: their items come from live data (web parity).
        let withArrays = manifests.filter { !$0.value.arrays.isEmpty }.keys.sorted()
        var arrayData: [String: [String: Any]] = [:]
        if !withArrays.isEmpty, let raw = try? await displaysRawBatchData(ids: withArrays),
           let reply = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let displays = reply["displays"] as? [String: Any] {
            for id in withArrays {
                if let entry = displays[id] as? [String: Any], let values = entry["data"] as? [String: Any] { arrayData[id] = values }
            }
        }
        return try TemplateCatalog(variablesData: data, manifests: manifests, arrayData: arrayData)
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
    public func displaysRawBatchData(ids: [String]) async throws -> Data {
        struct Body: Encodable { let display_types: [String]; let enabled_only: Bool }
        return try await readOK(APIRequest(.post, path: ["displays", "raw", "batch"],
                                           body: JSONEncoder().encode(Body(display_types: ids, enabled_only: true))))
    }
    public func validateTemplateRows(_ rows: [String]) async throws -> TemplateValidationResult {
        struct Body: Encodable { let template: [String] }
        let data = try await readOK(APIRequest(.post, path: ["templates", "validate"], body: JSONEncoder().encode(Body(template: rows))))
        return try TemplateValidationResult(rawData: data)
    }
}
