local spec_runner = require("guaraci_cli.spec_runner")

local SPEC_MODULES = {
    "tests.integration_mvp_spec",
    "tests.parser_linemap_spec",
    "tests.adapter_cgi_env_spec",
    "tests.guaraci_routing_spec",
    "tests.cli_main_spec",
    "tests.cli_check_spec",
    "tests.cli_test_spec",
    "tests.cli_new_spec",
    "tests.security_regression_spec",
    "tests.determinism_spec",
    "tests.template_functions_registry_spec",
    "tests.template_partials_spec",
    "tests.template_text_mode_spec",
    "tests.template_equivalence_spec",
    "tests.template_pentest_final_spec",
    -- Phase 10: Route/Middleware/Context
    "tests.context_store_spec",
    "tests.middleware_chain_spec",
    "tests.router_v2_spec",
    "tests.route_group_spec",
    -- Phase 11: Dataware ORM + Auto-CRUD
    "tests.dataware_spec",
    "tests.dataware_audit_spec",
    "tests.dataware_tenancy_spec",
    "tests.db_transaction_spec",
    "tests.query_builder_spec",
    "tests.auto_crud_spec",
    "tests.sqlite_driver_spec",
    "tests.sqlite_dataware_integration_spec",
    -- Phase 14: Validation + Binding + Security middleware
    "tests.validator_spec",
    "tests.binder_spec",
    "tests.security_middleware_spec",
    -- Phase 12: File upload foundation
    "tests.multipart_spec",
    "tests.file_validator_spec",
    "tests.file_storage_spec",
    "tests.file_manager_spec",
    "tests.adapter_cgi_multipart_spec",
    "tests.guaraci_upload_flow_spec",
    -- Phase 13: Error handling
    "tests.error_formatter_spec",
    "tests.error_handler_spec",
    "tests.guaraci_error_flow_spec",
    -- Phase 13 Block 3: Robustness
    "tests.guaraci_middleware_error_flow_spec",
    "tests.guaraci_stress_errors_spec"
}

return {
    run = function()
        return spec_runner.run(SPEC_MODULES)
    end
}
