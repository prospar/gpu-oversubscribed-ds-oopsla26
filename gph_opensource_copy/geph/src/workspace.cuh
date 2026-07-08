#pragma once

#define T_SIZE sizeof(T)
#define BUCKET_CAP bucket_cap
#define WORKSPACE_LEN (1 + (((virtual_bucket_n)+1) * BUCKET_CAP) + ((virtual_bucket_n) * 2))
#define WORKSPACE_SIZE ((WORKSPACE_LEN) * (T_SIZE))
#define TOTAL_WORKSPACES_NUMBER(total_workspaces_size) ((total_workspaces_size)/(WORKSPACE_SIZE))

#define WORKSPACE_LOCK(shared, k) ((T*)(shared) + (k) * (WORKSPACE_LEN))
#define WORKSPACE_BUCKET_I_J(shared, k, i, j) \
    ((T*)(shared) + (k) * (WORKSPACE_LEN) + 1 + (i) * (BUCKET_CAP) + (j))
#define WORKSPACE_EMPTY_I(shared, k, i) \
    ((T*)(shared) + (k) * (WORKSPACE_LEN) + 1 + (virtual_bucket_n) * (BUCKET_CAP) + (i) * 2)
#define WORKSPACE_THISCELL_I(shared, k, i) \
    ((T*)(shared) + (k) * (WORKSPACE_LEN) + 1 + (virtual_bucket_n) * (BUCKET_CAP) + (i) * 2 + 1)

#define WORKSPACE_BUFFER_BUCKET(shared, k) \
    ((T*)(shared) + (k) * (WORKSPACE_LEN) + 1 + (virtual_bucket_n) * (BUCKET_CAP) + (virtual_bucket_n) * 2)
#define WORKSPACE_BUCKET_I(shared, k, i) \
    ((T*)(shared) + (k) * (WORKSPACE_LEN) + 1 + (i) * (BUCKET_CAP))
#define BUCKET_J_TH_SLOT(bucket_address, j) \
    ((T*)(bucket_address) + (j))

#define WORKSPACE_LOCK_TRY_LIMIT 10