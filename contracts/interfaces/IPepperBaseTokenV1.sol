import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPepperBaseTokenV1 is IERC20 {
    function cap() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function mint(address account, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
}
