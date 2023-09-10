#include "TriangleInfo.h"

TriangleInfo::TriangleInfo() { optCost[0] = optCost[1] = optCost[2] = FLT_MIN; }

TriangleInfo::~TriangleInfo() {}

int TriangleInfo::getOptSize() {
  return sizeof(optCost) + sizeof(optTile);
}

int TriangleInfo::getSize() {
  return sizeof(optCost) + sizeof(optTile) + sizeof(edgeIndex) +
         sizeof(triIndex);
}