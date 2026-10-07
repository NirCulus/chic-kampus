export const MENU_SIZES = [
  { id: 'small', label: 'CK Steak Small', price: 15000, chickenIngredientId: 'chicken_sm' },
  { id: 'medium', label: 'CK Steak Medium', price: 17000, chickenIngredientId: 'chicken_md' },
  { id: 'large', label: 'CK Steak Large', price: 22000, chickenIngredientId: 'chicken_lg' },
]

export const SAUCES = [
  { id: 'classic_cheese', label: 'Classic Cheese', ingredientId: 'sauce_classic' },
  { id: 'hot_lava', label: 'Hot Lava', ingredientId: 'sauce_lava' },
  { id: 'magic_mushroom', label: 'Magic Mushroom', ingredientId: 'sauce_mushroom' },
  { id: 'black_thunder', label: 'Black Thunder', ingredientId: 'sauce_thunder' },
]

export const CARBS = [
  { id: 'rice', label: 'Nasi', ingredientId: 'rice' },
  { id: 'fries', label: 'Kentang Goreng', ingredientId: 'fries' },
]

export const PACKAGING_INGREDIENT_ID = 'packaging'

export const getSize = (id) => MENU_SIZES.find((item) => item.id === id)
export const getSauce = (id) => SAUCES.find((item) => item.id === id)
export const getCarb = (id) => CARBS.find((item) => item.id === id)
