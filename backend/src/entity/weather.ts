import {Entity, PrimaryGeneratedColumn, Column} from "typeorm";

@Entity()
export class Weather {
  @PrimaryGeneratedColumn()
  id: number;

  @Column()
  temperature: number;

  @Column()
  humidity: number;

  @Column()
  datetime: string;
}
