 import 'package:json_annotation/json_annotation.dart';
 import 'enums.gq.dart';
  part 'types.gq.g.dart';

@JsonSerializable()
      class MyProduct123 {
          final String id;
          final String name;
          final double price;
          final double? wasPrice;
          
          MyProduct123({required this.id, required this.name, required this.price, required this.wasPrice});
          
          factory MyProduct123.fromJson(Map<String, dynamic> json) => _$MyProduct123FromJson(json);
          
          Map<String, dynamic> toJson() => _$MyProduct123ToJson(this);
      }
    
@JsonSerializable()
      class MyProduct {
          final String id;
          final String name;
          
          MyProduct({required this.id, required this.name});
          
          factory MyProduct.fromJson(Map<String, dynamic> json) => _$MyProductFromJson(json);
          
          Map<String, dynamic> toJson() => _$MyProductToJson(this);
      }
    
@JsonSerializable()
      class Brand_ProductFragment {
          
          
          Brand_ProductFragment();
          
          factory Brand_ProductFragment.fromJson(Map<String, dynamic> json) => _$Brand_ProductFragmentFromJson(json);
          
          Map<String, dynamic> toJson() => _$Brand_ProductFragmentToJson(this);
      }
    
@JsonSerializable()
      class AhmedProduct {
          final String id;
          final String name;
          final Brand_ProductFragment brand;
          
          AhmedProduct({required this.id, required this.name, required this.brand});
          
          factory AhmedProduct.fromJson(Map<String, dynamic> json) => _$AhmedProductFromJson(json);
          
          Map<String, dynamic> toJson() => _$AhmedProductToJson(this);
      }
    
@JsonSerializable()
      class Product_id_name {
          final String id;
          final String name;
          
          Product_id_name({required this.id, required this.name});
          
          factory Product_id_name.fromJson(Map<String, dynamic> json) => _$Product_id_nameFromJson(json);
          
          Map<String, dynamic> toJson() => _$Product_id_nameToJson(this);
      }
    
@JsonSerializable()
      class GetProductsResponse {
          final List<MyProduct123> getProducts;
          final int getCount;
          
          GetProductsResponse({required this.getProducts, required this.getCount});
          
          factory GetProductsResponse.fromJson(Map<String, dynamic> json) => _$GetProductsResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$GetProductsResponseToJson(this);
      }
    
@JsonSerializable()
      class MyProductResp {
          final List<MyProduct> getAllProducts;
          
          MyProductResp({required this.getAllProducts});
          
          factory MyProductResp.fromJson(Map<String, dynamic> json) => _$MyProductRespFromJson(json);
          
          Map<String, dynamic> toJson() => _$MyProductRespToJson(this);
      }
    
@JsonSerializable()
      class ProductCreationResponse {
          final AhmedProduct createProduct;
          
          ProductCreationResponse({required this.createProduct});
          
          factory ProductCreationResponse.fromJson(Map<String, dynamic> json) => _$ProductCreationResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$ProductCreationResponseToJson(this);
      }
    
@JsonSerializable()
      class DeleteProductResponse {
          final Product_id_name deleteProduct;
          final int? deleteProduct2;
          
          DeleteProductResponse({required this.deleteProduct, required this.deleteProduct2});
          
          factory DeleteProductResponse.fromJson(Map<String, dynamic> json) => _$DeleteProductResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$DeleteProductResponseToJson(this);
      }
    

@JsonSerializable()
      class GetProductsResponse {
          final List<MyProduct123> getProducts;
          final int getCount;
          
          GetProductsResponse({required this.getProducts, required this.getCount});
          
          factory GetProductsResponse.fromJson(Map<String, dynamic> json) => _$GetProductsResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$GetProductsResponseToJson(this);
      }
    
@JsonSerializable()
      class MyProductResp {
          final List<MyProduct> getAllProducts;
          
          MyProductResp({required this.getAllProducts});
          
          factory MyProductResp.fromJson(Map<String, dynamic> json) => _$MyProductRespFromJson(json);
          
          Map<String, dynamic> toJson() => _$MyProductRespToJson(this);
      }
    
@JsonSerializable()
      class ProductCreationResponse {
          final AhmedProduct createProduct;
          
          ProductCreationResponse({required this.createProduct});
          
          factory ProductCreationResponse.fromJson(Map<String, dynamic> json) => _$ProductCreationResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$ProductCreationResponseToJson(this);
      }
    
@JsonSerializable()
      class DeleteProductResponse {
          final Product_id_name deleteProduct;
          final int? deleteProduct2;
          
          DeleteProductResponse({required this.deleteProduct, required this.deleteProduct2});
          
          factory DeleteProductResponse.fromJson(Map<String, dynamic> json) => _$DeleteProductResponseFromJson(json);
          
          Map<String, dynamic> toJson() => _$DeleteProductResponseToJson(this);
      }
      

