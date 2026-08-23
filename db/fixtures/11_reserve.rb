# Reserve.destroy_all
# Reserve.seed(:id,
#   { id: 1, 
#     reserved_date: Date.today+1,
#     reserved_space: 10,     
#     user_id: 1,
#     remarks: "remarks-1"
#   },
#   { id: 2, 
#     reserved_date: Date.today+1,
#     reserved_space: 10.5,     
#     user_id: 1,
#     remarks: "remarks-2"
#   },
#     { id: 3, 
#     reserved_date: Date.today+2,
#     reserved_space: 14,     
#     user_id: 3,
#     remarks: "remarks-3"
#   },
#   { id: 4, 
#     reserved_date: Date.today+4,
#     reserved_space: 17.5,     
#     user_id: 4,
#     remarks: "remarks-4"
#   },
#   { id: 5, 
#     reserved_date: Date.today+5,
#     reserved_space: 15.5,     
#     user_id: 1,
#     remarks: "remarks-5"
#   },  
#     { id: 6, 
#     reserved_date: Date.today+13,
#     reserved_space: 22,     
#     user_id: 2,
#     remarks: "remarks-6"
#   }  
# )

# 10.times do |i|
#   Reserve.seed(:id,
#     { id: 7+i, 
#       reserved_date: Date.today+6,
#       reserved_space: (10.5+i*0.5),     
#       user_id: 4,
#     remarks: "remarks-#{7+i}"
#     }
#   )
# end