#pragma once

template<typename T>
struct HalfTypeT {
    using HT = uint64_t;
};

template<>
struct HalfTypeT<uint32_t> {
    using HT = uint16_t;
};

template<>
struct HalfTypeT<uint64_t> {
    using HT = uint32_t;
};

template <typename T>
__device__ __host__
void splitKV(T kv, typename HalfTypeT<T>::HT& k, typename HalfTypeT<T>::HT& v) {
  using HT = typename HalfTypeT<T>::HT;
  if constexpr(std::is_same_v<T, uint32_t>) {
    k = static_cast<HT>(kv >> 16);
    v = static_cast<HT>(kv & ((1ULL << 16)-1));
    return;
  } else if constexpr(std::is_same_v<T, uint64_t>)  {
    k = static_cast<HT>(kv >> 32);
    v = static_cast<HT>(kv & ((1ULL << 32)-1));
    return;
  } else {
    assert(false);
    return;
  }
}

template <typename T>
__device__ __host__
T combineKV(typename HalfTypeT<T>::HT k, typename HalfTypeT<T>::HT v) {
  using HT = typename HalfTypeT<T>::HT;
  if constexpr(std::is_same_v<T, uint32_t>) {
    return (static_cast<T>(k) << 16) | v ;
  } else if constexpr(std::is_same_v<T, uint64_t>)  {
    return (static_cast<T>(k) << 32) | v ;
  } else {
    assert(false);
  }
}