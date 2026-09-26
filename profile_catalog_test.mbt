///|
fn catalog_profile(
  id : String,
  version : String,
) -> @moonforensics.JsonlMappingProfile {
  @moonforensics.JsonlMappingProfile::{
    id,
    version,
    source: @moonforensics.SourceMappingProfile::{
      system: @moonforensics.ProfileStringValue::Constant("fixture"),
      component: @moonforensics.ProfileStringValue::Constant("catalog"),
      host: None,
      instrumentation_scope: None,
    },
    event_id: @moonforensics.ProfileStringValue::Constant("event_id"),
    event_time: None,
    observed_time: None,
    severity: None,
    resource: None,
    category: @moonforensics.EventCategory::Other("catalog"),
    event_type: @moonforensics.ProfileStringValue::Constant("fixture.event"),
    action: None,
    outcome: @moonforensics.EventOutcome::Unknown,
    body_path: None,
  }
}

///|
test "profile catalog preserves registration order and resolves exact versions" {
  let v1 = catalog_profile("health", "1.0.0")
  let v2 = catalog_profile("health", "2.0.0")
  let other = catalog_profile("config", "1.0.0")
  let catalog = try! @moonforensics.new_profile_catalog([v2, other, v1])
  let listed = @moonforensics.list_profiles(catalog)
  assert_eq(listed.length(), 3)
  assert_eq(listed[0].version, "2.0.0")
  assert_eq(listed[1].id, "config")
  assert_eq(@moonforensics.resolve_profile(catalog, "health", "1.0.0"), v1)
  assert_eq(@moonforensics.resolve_profile(catalog, "health", "2.0.0"), v2)
}

///|
test "profile catalog registers profiles without overwriting identities" {
  let first = catalog_profile("health", "1.0.0")
  let second = catalog_profile("config", "1.0.0")
  let catalog = try! @moonforensics.new_profile_catalog([first])
  let expanded = try! @moonforensics.register_profile(catalog, second)
  assert_eq(@moonforensics.list_profiles(expanded).length(), 2)
  assert_eq(@moonforensics.resolve_profile(expanded, "config", "1.0.0"), second)
  try @moonforensics.register_profile(expanded, second) catch {
    @moonforensics.ProfileCatalogError::DuplicateProfile(id~, version~) => {
      assert_eq(id, "config")
      assert_eq(version, "1.0.0")
    }
    _ => fail("expected duplicate profile")
  } noraise {
    _ => fail("expected duplicate profile")
  }
}

///|
test "profile catalog reports missing versions and invalid profiles" {
  let catalog = try! @moonforensics.new_profile_catalog([
    catalog_profile("health", "1.0.0"),
  ])
  try @moonforensics.resolve_profile(catalog, "health", "2.0.0") catch {
    @moonforensics.ProfileCatalogError::MissingProfile(id~, version~) => {
      assert_eq(id, "health")
      assert_eq(version, "2.0.0")
    }
    _ => fail("expected missing profile")
  } noraise {
    _ => fail("expected missing profile")
  }

  let invalid = catalog_profile("", "1.0.0")
  try @moonforensics.register_profile(catalog, invalid) catch {
    @moonforensics.ProfileCatalogError::InvalidProfile(field~, reason~) => {
      assert_eq(field, "id")
      assert_true(reason.contains("must not be empty"))
    }
    _ => fail("expected invalid profile")
  } noraise {
    _ => fail("expected invalid profile")
  }
}
