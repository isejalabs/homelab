set default-list

# kopiur backup/restore maintenance recipes
mod kopiur "kopiur.just"

# Longhorn volume snapshot recipes (local hourly snapshots, no offsite copy)
mod longhorn-snapshot "longhorn-snapshot.just"

# Keycloak database restore recipes (#1938)
mod keycloak "keycloak.just"
