#include <Eigen/Core>

void refine_patch(const Eigen::MatrixXd& V, const Eigen::MatrixXi& F, float targetEdgeLength, //
    Eigen::MatrixXd& V_fine, Eigen::MatrixXi& F_fine);