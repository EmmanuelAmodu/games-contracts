import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPepperBaseTokenV1 is IERC20 {
    function cap() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function mint(address account, uint256 amount) external;
    function burn(uint256 amount) external;
}
