///|
/// A validated collection of versioned JSONL mapping profiles.
///
/// Catalog order is registration order. Resolving always requires an exact
/// profile ID and version so a schema change cannot silently select another
/// mapping.
pub struct ProfileCatalog {
  profiles : Array[JsonlMappingProfile]
} derive(Debug, Eq)

///|
/// A profile cannot be registered or resolved safely.
pub(all) suberror ProfileCatalogError {
  InvalidProfile(field~ : String, reason~ : String)
  DuplicateProfile(id~ : String, version~ : String)
  MissingProfile(id~ : String, version~ : String)
} derive(Debug, Eq)

///|
fn validate_catalog_profile(
  profile : JsonlMappingProfile,
) -> Unit raise ProfileCatalogError {
  try validate_jsonl_profile(profile) catch {
    ProfileMapError::InvalidProfile(field~, reason~) =>
      raise ProfileCatalogError::InvalidProfile(field~, reason~)
    ProfileMapError::MissingValue(line_number~, path~) =>
      raise ProfileCatalogError::InvalidProfile(
        field=path,
        reason="profile validation unexpectedly required an evidence line \{line_number}",
      )
    ProfileMapError::InvalidValue(line_number~, path~, value~) =>
      raise ProfileCatalogError::InvalidProfile(
        field=path,
        reason="profile validation unexpectedly required an evidence value at line \{line_number}: \{value}",
      )
  } noraise {
    _ => ()
  }
}

///|
fn has_profile(
  profiles : Array[JsonlMappingProfile],
  id : String,
  version : String,
) -> Bool {
  for profile in profiles {
    if profile.id == id && profile.version == version {
      return true
    }
  }
  false
}

///|
fn copy_profiles(
  profiles : Array[JsonlMappingProfile],
) -> Array[JsonlMappingProfile] {
  let copied : Array[JsonlMappingProfile] = []
  for profile in profiles {
    copied.push(profile)
  }
  copied
}

///|
fn validate_catalog_entries(
  profiles : Array[JsonlMappingProfile],
) -> Unit raise ProfileCatalogError {
  let validated : Array[JsonlMappingProfile] = []
  for profile in profiles {
    validate_catalog_profile(profile)
    if has_profile(validated, profile.id, profile.version) {
      raise ProfileCatalogError::DuplicateProfile(
        id=profile.id,
        version=profile.version,
      )
    }
    validated.push(profile)
  }
}

///|
/// Creates a catalog after validating every profile and its exact identity.
pub fn new_profile_catalog(
  profiles : Array[JsonlMappingProfile],
) -> ProfileCatalog raise ProfileCatalogError {
  validate_catalog_entries(profiles)
  { profiles, }
}

///|
/// Registers one new profile without replacing an existing ID/version pair.
pub fn register_profile(
  catalog : ProfileCatalog,
  profile : JsonlMappingProfile,
) -> ProfileCatalog raise ProfileCatalogError {
  validate_catalog_profile(profile)
  if has_profile(catalog.profiles, profile.id, profile.version) {
    raise ProfileCatalogError::DuplicateProfile(
      id=profile.id,
      version=profile.version,
    )
  }
  let profiles = copy_profiles(catalog.profiles)
  profiles.push(profile)
  { profiles, }
}

///|
/// Resolves a profile by exact ID and version.
pub fn resolve_profile(
  catalog : ProfileCatalog,
  id : String,
  version : String,
) -> JsonlMappingProfile raise ProfileCatalogError {
  for profile in catalog.profiles {
    if profile.id == id && profile.version == version {
      return profile
    }
  }
  raise ProfileCatalogError::MissingProfile(id~, version~)
}

///|
/// Returns profiles in their stable registration order.
pub fn list_profiles(catalog : ProfileCatalog) -> Array[JsonlMappingProfile] {
  copy_profiles(catalog.profiles)
}
