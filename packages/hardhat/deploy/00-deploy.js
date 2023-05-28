module.exports = async ({ getNamedAccounts, deployments, ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("Footwears", {
    from: deployer,
    args: [], // remove the argument or specify the necessary arguments
    log: true,
  });

  // Uncomment and modify the following lines if you want to deploy additional contracts
  // await deploy("Storage", {
  //   from: deployer,
  //   args: ["Hello", ethers.utils.parseEther("1.5")],
  //   log: true,
  // });

  // await deploy("SupportToken", {
  //   from: deployer,
  //   args: ["Hello", ethers.utils.parseEther("1.5")],
  //   log: true,
  // });
};

module.exports.tags = ["Footwears"];
